# frozen_string_literal: true

module Hiero
  # Base class for everything that changes state on the network.
  #
  # == Freezing
  #
  # A transaction is a mutable builder until {#freeze_with}, which fixes the
  # payer, the valid start, the nodes it may be sent to, and the fee. After that
  # every setter refuses, because the signatures collected next cover exactly
  # those bytes.
  #
  # Note the name. Ruby already owns `#freeze`, and this object keeps mutating
  # after freezing -- signatures accumulate -- so overriding `#frozen?` would lie
  # to `dup`, to serialization libraries, and to anything else that asks.
  #
  # == The signing matrix
  #
  # A transaction is not one message. Each node receives a body naming *itself* as
  # nodeAccountID, so each needs its own signature, and a chunked transaction
  # multiplies that by its number of chunks:
  #
  #   index = transaction_ids.index * node_account_ids.length + node_account_ids.index
  #
  # Bodies are built and signed one at a time, for whichever node the current
  # attempt is going to. The JavaScript SDK offers this as an option and defaults
  # to materialising the whole matrix up front, because its toBytes() is
  # synchronous and a remote signer is not. Ruby has no such split -- a remote
  # signer is an ordinary blocking call -- so lazy is the only mode, and an entire
  # configuration flag and its interactions disappear with it.
  class Transaction < Executable
    DEFAULT_VALID_DURATION = 120 # seconds; the network's own maximum

    # protobuf oneof member => Transaction subclass, populated by {.data_case}.
    # This is how {.from_bytes} dispatches without importing every subclass.
    REGISTRY = {}

    attr_reader :transaction_ids, :transaction_id, :max_transaction_fee,
                :transaction_valid_duration, :transaction_memo

    def initialize
      super
      @transaction_ids = CircularList.new
      @transaction_id = nil
      @max_transaction_fee = nil
      @transaction_valid_duration = Duration.new(DEFAULT_VALID_DURATION)
      @transaction_memo = ""
      @signers = []
      @signatures = {}
      @frozen_body = false
    end

    class << self
      # Declares which TransactionBody oneof this subclass fills, and registers it
      # so {.from_bytes} can find it.
      #
      # Note the casing: HAPI declares most fields in camelCase, so this is
      # :cryptoTransfer rather than :crypto_transfer. It has to match exactly what
      # google-protobuf reports for `body.data`.
      def data_case(name = nil)
        return @data_case if name.nil?

        @data_case = name
        REGISTRY[name] = self
      end

      # @param bytes [String] a serialized Transaction or TransactionList
      def from_bytes(bytes)
        Hiero.protobuf!
        list = decode_list(bytes)
        raise Error, "no transactions in these bytes" if list.empty?

        body = ::Proto::TransactionBody.decode(signed_body_bytes(list.first))
        klass = REGISTRY.fetch(body.data) do
          raise Error, "unsupported transaction type: #{body.data}"
        end

        klass.from_protobuf(body, list)
      end

      def decode_list(bytes)
        # A single Transaction and a TransactionList are different messages, and
        # both are in circulation, so try the envelope first and fall back.
        parsed = ::Proto::TransactionList.decode(bytes)
        parsed.transaction_list.empty? ? [::Proto::Transaction.decode(bytes)] : parsed.transaction_list.to_a
      rescue Google::Protobuf::ParseError
        [::Proto::Transaction.decode(bytes)]
      end

      def signed_body_bytes(transaction)
        ::Proto::SignedTransaction.decode(transaction.signedTransactionBytes).bodyBytes
      end
    end

    # --- building ---------------------------------------------------------------

    def frozen_body? = @frozen_body

    def transaction_id=(value)
      require_not_frozen!
      @transaction_id = value.is_a?(TransactionId) ? value : TransactionId.from_string(value.to_s)
      @transaction_ids.items = [@transaction_id]
      @transaction_id
    end

    def max_transaction_fee=(value)
      require_not_frozen!
      @max_transaction_fee = Hbar.coerce(value)
    end

    def transaction_valid_duration=(value)
      require_not_frozen!
      @transaction_valid_duration = Duration.coerce(value)
    end

    def transaction_memo=(value)
      require_not_frozen!
      @transaction_memo = value.to_s
    end

    def set_transaction_id(value) = (self.transaction_id = value; self)
    def set_max_transaction_fee(value) = (self.max_transaction_fee = value; self)
    def set_transaction_valid_duration(value) = (self.transaction_valid_duration = value; self)
    def set_transaction_memo(value) = (self.transaction_memo = value; self)

    # Fixes everything the signatures will cover.
    #
    # @param client [Client, nil] supplies the payer, the nodes and the default fee
    def freeze_with(client = nil)
      return self if frozen_body?

      if @transaction_id.nil?
        payer = client&.operator_account_id
        raise Error, "cannot freeze without a transaction id or a client with an operator" if payer.nil?

        self.transaction_id = TransactionId.generate(payer)
      end

      if @node_account_ids.empty?
        raise Error, "cannot freeze without node account ids or a client" if client.nil?

        nodes = client.network.healthiest(client.network.account_ids.length)
        raise Error, "this client has no nodes to send to" if nodes.empty?

        self.node_account_ids = nodes.map(&:account_id)
      end

      @max_transaction_fee ||= client&.default_max_transaction_fee || DEFAULT_MAX_FEE

      # Locked together: the signatures about to be collected name these nodes and
      # this id, so neither can move afterwards.
      @node_account_ids.lock!
      @transaction_ids.lock!
      @frozen_body = true
      self
    end

    # --- signing ----------------------------------------------------------------

    # @param private_key [PrivateKey]
    def sign(private_key)
      sign_with(private_key.public_key) { |bytes| private_key.sign(bytes) }
    end

    # Signs through a callable, so the key may live in an HSM or a wallet.
    #
    # @param public_key [PublicKey]
    def sign_with(public_key, &signer)
      require_frozen!
      return self if @signers.any? { |existing, _| existing == public_key }

      @signers << [public_key, signer]
      self
    end

    # @return [Boolean] whether this key has already signed
    def signed_by?(public_key) = @signers.any? { |existing, _| existing == public_key }

    # Attaches a signature produced elsewhere, for the multi-party workflow where
    # bytes are shipped out, signed offline, and merged back.
    def add_signature(public_key, signature)
      require_frozen!
      @signatures[public_key] = signature
      self
    end

    # @return [Hash{PublicKey => String}] signatures over the current body
    def signatures
      require_frozen!
      body = body_bytes_for_current_attempt
      @signers.to_h { |public_key, signer| [public_key, signer.call(body)] }.merge(@signatures)
    end

    # --- serialization ----------------------------------------------------------

    # @return [String] a serialized TransactionList covering every node and chunk
    def to_bytes
      require_frozen!
      Hiero.protobuf!

      transactions = each_body_index.map { |index| build_transaction(index) }
      ::Proto::TransactionList.encode(::Proto::TransactionList.new(transaction_list: transactions))
    end

    # --- Executable ---------------------------------------------------------------

    def before_execute(client)
      freeze_with(client) unless frozen_body?

      if client.auto_validate_checksums && client.ledger_id
        validate_checksums(client.ledger_id)
      end

      operator = client.operator
      return if operator.nil? || signed_by?(operator.public_key)

      sign_with(operator.public_key) { |bytes| operator.sign(bytes) }
    end

    def make_request = build_transaction(current_body_index)

    def execution_state(_request, response)
      status = Status[response.nodeTransactionPrecheckCode]

      state =
        case status
        when Status::OK then :finished
        when Status::BUSY, Status::UNKNOWN, Status::PLATFORM_NOT_ACTIVE,
             Status::PLATFORM_TRANSACTION_NOT_CREATED, Status::INVALID_NODE_ACCOUNT then :retry
        else :error
        end

      [status, state]
    end

    def map_status_error(_request, response, node_account_id)
      PrecheckStatusError.new(status: Status[response.nodeTransactionPrecheckCode],
                              node_account_id: node_account_id,
                              transaction_id: @transaction_id)
    end

    def map_response(_response, node_account_id, request)
      TransactionResponse.new(
        transaction_id: @transaction_id,
        node_account_id: node_account_id,
        transaction_hash: OpenSSL::Digest.digest("SHA384", request.signedTransactionBytes)
      )
    end

    # --- the body, which subclasses fill ------------------------------------------

    # @return [Object] the protobuf fragment for this transaction's oneof member
    def make_transaction_data = raise(NotImplementedError, "#{self.class} must implement #make_transaction_data")

    # Override where a transaction carries entity ids.
    def validate_checksums(ledger_id); end

    private

    def require_not_frozen!
      return unless frozen_body?

      raise TransactionFrozenError,
            "#{self.class} is frozen; its signatures cover the current body and would be invalidated"
    end

    def require_frozen!
      raise Error, "#{self.class} must be frozen first; call #freeze_with" unless frozen_body?
    end

    # index = transaction_ids.index * node_account_ids.length + node_account_ids.index
    def current_body_index
      (@transaction_ids.index * @node_account_ids.length) + @node_account_ids.index
    end

    def each_body_index = (0...(@transaction_ids.length * @node_account_ids.length))

    def body_for(index)
      node_index = index % @node_account_ids.length
      id_index = index / @node_account_ids.length

      ::Proto::TransactionBody.new(
        transactionID: @transaction_ids.to_a[id_index].to_protobuf,
        nodeAccountID: node_protobuf(@node_account_ids.to_a[node_index]),
        transactionFee: (@max_transaction_fee || DEFAULT_MAX_FEE).to_tinybars,
        transactionValidDuration: ::Proto::Duration.new(seconds: @transaction_valid_duration.seconds),
        memo: @transaction_memo,
        # The oneof member this subclass declared, set dynamically because the
        # field name differs per transaction type.
        self.class.data_case => make_transaction_data
      )
    end

    def body_bytes_for_current_attempt = ::Proto::TransactionBody.encode(body_for(current_body_index))

    def build_transaction(index)
      body_bytes = ::Proto::TransactionBody.encode(body_for(index))
      signed = ::Proto::SignedTransaction.new(bodyBytes: body_bytes, sigMap: signature_map(body_bytes))

      ::Proto::Transaction.new(signedTransactionBytes: ::Proto::SignedTransaction.encode(signed))
    end

    def signature_map(body_bytes)
      pairs = @signers.map { |public_key, signer| signature_pair(public_key, signer.call(body_bytes)) }
      pairs += @signatures.map { |public_key, signature| signature_pair(public_key, signature) }

      ::Proto::SignatureMap.new(sigPair: pairs)
    end

    def signature_pair(public_key, signature)
      raw = public_key.to_bytes_raw
      pair = ::Proto::SignaturePair.new(pubKeyPrefix: raw)

      if public_key.ed25519?
        pair.ed25519 = signature
      else
        pair.ECDSA_secp256k1 = signature
      end

      pair
    end

    def node_protobuf(account_id)
      ::Proto::AccountID.new(shardNum: account_id.shard, realmNum: account_id.realm, accountNum: account_id.num)
    end

  end

  # Defined after the class body so it can use Hbar, which Zeitwerk autoloads on
  # first reference.
  Transaction::DEFAULT_MAX_FEE = Hbar.new(2)
end
