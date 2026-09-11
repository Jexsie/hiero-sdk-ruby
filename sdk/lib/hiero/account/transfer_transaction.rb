# frozen_string_literal: true

module Hiero
  module Account
    # Moves hbar between accounts.
    #
    # Every transfer is atomic and must balance: the amounts sum to zero, because
    # the network moves value rather than creating it. An unbalanced transfer is
    # rejected, so {#validate_balanced!} catches it here where the error can say
    # which way it is out.
    class TransferTransaction < Transaction
      data_case :cryptoTransfer

      attr_reader :hbar_transfers

      def initialize(hbar_transfers: {}, **options)
        super()
        @hbar_transfers = {}
        hbar_transfers.each { |account_id, amount| add_hbar_transfer(account_id, amount) }
        options.each { |name, value| public_send(:"#{name}=", value) }
      end

      # Adds to whatever this account is already sending or receiving, rather than
      # replacing it: two credits to the same account are one net credit, which is
      # what the network expects to see.
      #
      # @param account_id [AccountId, String, Integer]
      # @param amount [Hbar, Integer] negative to send, positive to receive
      def add_hbar_transfer(account_id, amount)
        require_not_frozen!

        account_id = AccountId.coerce(account_id)
        amount = Hbar.coerce(amount)
        existing = @hbar_transfers[account_id]
        @hbar_transfers[account_id] = existing ? existing + amount : amount
        self
      end

      # @return [Hbar] how far from balanced this transfer is; zero when valid
      def imbalance
        @hbar_transfers.values.reduce(Hbar::ZERO) { |sum, amount| sum + amount }
      end

      def balanced? = imbalance.zero?

      def validate_balanced!
        return self if balanced?

        raise Error,
              "transfers must sum to zero; this one is out by #{imbalance}. " \
              "Every hbar debited has to be credited somewhere."
      end

      def before_execute(client)
        raise Error, "a TransferTransaction needs at least one transfer" if @hbar_transfers.empty?

        validate_balanced!
        super
      end

      def validate_checksums(ledger_id)
        @hbar_transfers.each_key { |account_id| account_id.validate_checksum!(ledger_id) }
      end

      def make_transaction_data
        amounts = @hbar_transfers.map do |account_id, amount|
          ::Proto::AccountAmount.new(
            accountID: ::Proto::AccountID.new(shardNum: account_id.shard,
                                              realmNum: account_id.realm,
                                              accountNum: account_id.num),
            amount: amount.to_tinybars
          )
        end

        ::Proto::CryptoTransferTransactionBody.new(
          transfers: ::Proto::TransferList.new(accountAmounts: amounts)
        )
      end

      def call(channel, request, deadline:)
        channel.crypto.crypto_transfer(request, deadline: deadline)
      end

      def self.from_protobuf(body, _list)
        transaction = new
        body.cryptoTransfer.transfers&.accountAmounts&.each do |entry|
          transaction.add_hbar_transfer(
            AccountId.new(shard: entry.accountID.shardNum,
                          realm: entry.accountID.realmNum,
                          num: entry.accountID.accountNum),
            Hbar.from_tinybars(entry.amount)
          )
        end
        transaction
      end
    end
  end
end
