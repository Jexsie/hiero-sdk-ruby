# frozen_string_literal: true

module Hiero
  # Creates an account.
  #
  # The new account's number is not known until the transaction reaches
  # consensus, so it comes back on the receipt rather than from this object:
  #
  #   receipt = AccountCreateTransaction.new(key: key.public_key, initial_balance: Hbar.new(10))
  #                                     .execute(client)
  #                                     .receipt(client)
  #   receipt.account_id
  #
  # The key given here controls the new account. It may be a {PublicKey} or a
  # {KeyList}, so an account can require several signatures or any threshold of
  # them from the moment it exists.
  #
  # The new account does not sign its own creation -- it does not exist yet, and
  # the payer funds it. The exception is {#receiver_signature_required}, which
  # asks the network to require the new key's signature on incoming transfers;
  # setting that means the new key must sign this transaction too, since it is
  # committing that key to a rule it will be bound by.
  class AccountCreateTransaction < Transaction
    data_case :cryptoCreateAccount

    # The network's own default, and the maximum it accepts.
    DEFAULT_AUTO_RENEW_PERIOD = 7_776_000 # 90 days

    attr_reader :key, :initial_balance, :account_memo, :auto_renew_period,
                :max_automatic_token_associations, :receiver_signature_required

    def initialize(key: nil, initial_balance: nil, **options)
      super()
      @key = nil
      @initial_balance = Hbar::ZERO
      @account_memo = ""
      @auto_renew_period = Duration.new(DEFAULT_AUTO_RENEW_PERIOD)
      @max_automatic_token_associations = 0
      @receiver_signature_required = false

      # Through the setters, not around them. Assigning the ivars directly meant
      # a bad key or a negative balance was accepted from the constructor and
      # rejected from the setter, which is the same value being valid or not
      # depending on how it arrived.
      self.key = key unless key.nil?
      self.initial_balance = initial_balance unless initial_balance.nil?
      options.each { |name, value| public_send(:"#{name}=", value) }
    end

    def key=(value)
      require_not_frozen!
      raise ArgumentError, "an account key must be a Hiero::Key, got #{value.class}" unless value.is_a?(Key)

      @key = value
    end

    def initial_balance=(value)
      require_not_frozen!
      amount = Hbar.coerce(value)
      raise ArgumentError, "an initial balance cannot be negative" if amount.negative?

      @initial_balance = amount
    end

    def account_memo=(value)
      require_not_frozen!
      @account_memo = value.to_s
    end

    def auto_renew_period=(value)
      require_not_frozen!
      @auto_renew_period = Duration.coerce(value)
    end

    def max_automatic_token_associations=(value)
      require_not_frozen!
      @max_automatic_token_associations = Integer(value)
    end

    # Requires the account's own signature on transfers into it, which stops
    # anyone sending it tokens or hbar unasked.
    def receiver_signature_required=(value)
      require_not_frozen!
      @receiver_signature_required = value ? true : false
    end

    def set_key(value) = (self.key = value; self)
    def set_initial_balance(value) = (self.initial_balance = value; self)
    def set_account_memo(value) = (self.account_memo = value; self)
    def set_auto_renew_period(value) = (self.auto_renew_period = value; self)
    def set_max_automatic_token_associations(value) = (self.max_automatic_token_associations = value; self)
    def set_receiver_signature_required(value) = (self.receiver_signature_required = value; self)

    def before_execute(client)
      raise Error, "an AccountCreateTransaction needs a key for the new account" if @key.nil?

      super
    end

    def make_transaction_data
      ::Proto::CryptoCreateTransactionBody.new(
        key: @key.to_protobuf_key,
        initialBalance: @initial_balance.to_tinybars,
        memo: @account_memo,
        autoRenewPeriod: ::Proto::Duration.new(seconds: @auto_renew_period.seconds),
        max_automatic_token_associations: @max_automatic_token_associations,
        receiverSigRequired: @receiver_signature_required
      )
    end

    def call(channel, request, deadline:)
      channel.crypto.create_account(request, deadline: deadline)
    end

    def self.from_protobuf(body, _list)
      create = body.cryptoCreateAccount
      new(
        key: Key.from_protobuf_key(create.key),
        initial_balance: Hbar.from_tinybars(create.initialBalance),
        account_memo: create.memo,
        max_automatic_token_associations: create.max_automatic_token_associations,
        receiver_signature_required: create.receiverSigRequired
      )
    end
  end
end
