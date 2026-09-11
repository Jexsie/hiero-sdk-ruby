# frozen_string_literal: true

module Hiero
  # Base class for reads from a consensus node.
  #
  # Most queries are paid, and the exchange is two round trips: ask the node what
  # the answer costs, then ask again with a signed payment attached. The node
  # quotes its own price, so there is no fee schedule to keep in step here.
  #
  # A few queries are free -- balances, receipts -- and say so by overriding
  # {#payment_required?}, which is the only difference between the two paths.
  #
  # Subclasses build their protobuf through {#build_query}, taking the header
  # rather than making one, so the same body can be sent either as a real query or
  # as a cost enquiry. That is what {CostQuery} relies on.
  class Query < Executable
    # The quoted price plus a tenth. Fees move with the exchange rate between the
    # two round trips, and a payment a hair under the real cost is rejected
    # outright -- the headroom buys tolerance for that drift.
    COST_HEADROOM = Rational(11, 10)

    attr_reader :query_payment, :max_query_payment, :payment_transaction_id

    def initialize
      super
      @query_payment = nil
      @max_query_payment = nil
      @payment_transaction_id = nil
      @payments = {}
      @operator = nil
      @response_type = :ANSWER_ONLY
    end

    # @return [Boolean] whether the node charges for this query
    def payment_required? = true

    # Pays exactly this, skipping the cost enquiry and its round trip.
    #
    # Worth doing for a query in a hot path where the price is known and stable.
    # Too little and the node rejects it; too much and the difference is spent.
    def query_payment=(value)
      @query_payment = Hbar.coerce(value)
    end

    # A ceiling for this query alone, overriding the client's.
    def max_query_payment=(value)
      @max_query_payment = Hbar.coerce(value)
    end

    def set_query_payment(value) = (self.query_payment = value; self)
    def set_max_query_payment(value) = (self.max_query_payment = value; self)

    # Asks the node what this query costs, without running it.
    #
    # @return [Hbar] the quoted price plus {COST_HEADROOM}
    def cost(client)
      choose_nodes_from(client) if @node_account_ids.empty?
      quoted = CostQuery.new(self).execute(client)

      Hbar.from_tinybars((quoted.to_tinybars * COST_HEADROOM).ceil)
    end

    def before_execute(client)
      validate_query!
      @node_account_ids.empty? && choose_nodes_from(client)

      if client.auto_validate_checksums && client.ledger_id
        validate_checksums(client.ledger_id)
      end

      return unless payment_required?
      return unless @payments.empty?

      @operator = client.operator
      raise Error, "#{self.class} is a paid query and needs a client with an operator" if @operator.nil?

      @payment_transaction_id = TransactionId.generate(@operator.account_id)
      @query_payment ||= negotiate_price(client)

      # One payment per node, because each names its own node in the body it
      # signs -- the same reason a transaction is several messages.
      @node_account_ids.each do |node_account_id|
        @payments[node_account_id] = payment_transaction(node_account_id, @query_payment)
      end
    end

    def make_request = build_query(query_header)

    # @param header [Proto::QueryHeader]
    # @return [Proto::Query]
    def build_query(_header) = raise(NotImplementedError, "#{self.class} must implement #build_query")

    def execution_state(_request, response)
      status = Status[response_header(response).nodeTransactionPrecheckCode]

      state =
        case status
        when Status::OK then :finished
        when Status::BUSY, Status::PLATFORM_NOT_ACTIVE, Status::PLATFORM_TRANSACTION_NOT_CREATED,
             Status::INVALID_NODE_ACCOUNT then :retry
        else :error
        end

      [status, state]
    end

    def map_status_error(_request, response, node_account_id)
      PrecheckStatusError.new(status: Status[response_header(response).nodeTransactionPrecheckCode],
                              node_account_id: node_account_id)
    end

    # @return [Proto::ResponseHeader] the header nested inside this response type
    def response_header(_response) = raise(NotImplementedError, "#{self.class} must implement #response_header")

    # Override where a query carries entity ids.
    def validate_checksums(ledger_id); end

    # Override to reject a query that is missing something it needs.
    def validate_query!; end

    # The header for the node this attempt is going to.
    def query_header
      return ::Proto::QueryHeader.new(responseType: @response_type) unless payment_required?

      ::Proto::QueryHeader.new(responseType: @response_type,
                               payment: @payments[@node_account_ids.current])
    end

    # Builds a signed payment addressed to one node.
    #
    # Public because {CostQuery} needs one for the free enquiry, addressed to
    # account zero with nothing in it.
    def payment_transaction(node_account_id, amount, operator: @operator)
      node = account_protobuf(node_account_id)
      body = ::Proto::TransactionBody.new(
        transactionID: @payment_transaction_id.to_protobuf,
        nodeAccountID: node,
        transactionFee: PAYMENT_MAX_FEE.to_tinybars,
        transactionValidDuration: ::Proto::Duration.new(seconds: Transaction::DEFAULT_VALID_DURATION),
        cryptoTransfer: ::Proto::CryptoTransferTransactionBody.new(
          transfers: ::Proto::TransferList.new(
            accountAmounts: [
              ::Proto::AccountAmount.new(accountID: node, amount: amount.to_tinybars),
              ::Proto::AccountAmount.new(accountID: account_protobuf(operator&.account_id || node_account_id),
                                         amount: -amount.to_tinybars)
            ]
          )
        )
      )

      bytes = ::Proto::TransactionBody.encode(body)
      signed = ::Proto::SignedTransaction.new(bodyBytes: bytes, sigMap: payment_signature_map(bytes, operator))

      ::Proto::Transaction.new(signedTransactionBytes: ::Proto::SignedTransaction.encode(signed))
    end

    def payment_transaction_id=(value)
      @payment_transaction_id = value
    end

    def response_type=(value)
      @response_type = value
    end

    private

    def negotiate_price(client)
      ceiling = @max_query_payment || client.max_query_payment
      price = cost(client)

      return price if ceiling.nil? || price <= ceiling

      raise MaxQueryPaymentExceededError.new(cost: price, maximum: ceiling, query: self.class)
    end

    def choose_nodes_from(client)
      nodes = client.network.healthiest(client.network.account_ids.length)
      raise Error, "this client has no nodes to send to" if nodes.empty?

      self.node_account_ids = nodes.map(&:account_id)
    end

    def payment_signature_map(bytes, operator)
      # A cost enquiry carries an unsigned payment: the node checks that one is
      # present, not that it is valid, because it is answering free of charge.
      return ::Proto::SignatureMap.new if operator.nil?

      public_key = operator.public_key
      pair = ::Proto::SignaturePair.new(pubKeyPrefix: public_key.to_bytes_raw)
      signature = operator.sign(bytes)
      public_key.ed25519? ? pair.ed25519 = signature : pair.ECDSA_secp256k1 = signature

      ::Proto::SignatureMap.new(sigPair: [pair])
    end

    def account_protobuf(account_id)
      account_id = AccountId.coerce(account_id)
      ::Proto::AccountID.new(shardNum: account_id.shard, realmNum: account_id.realm, accountNum: account_id.num)
    end
  end

  # A ceiling on the payment transaction itself, distinct from the query price it
  # carries. Defined after the class body so it can use Hbar.
  Query::PAYMENT_MAX_FEE = Hbar.new(1)
end
