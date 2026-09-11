# frozen_string_literal: true

module Hiero
  # Reads everything a consensus node knows about an account.
  #
  # The first paid query in this SDK, and the reason the payment path exists: the
  # node quotes a price, the client signs a transfer for it, and only then does
  # the node answer.
  #
  # {AccountBalanceQuery} is free and reads the balance alone. Prefer it when the
  # balance is all that is wanted -- this one costs money for the rest.
  class AccountInfoQuery < Query
    attr_reader :account_id

    def initialize(account_id: nil)
      super()
      self.account_id = account_id if account_id
    end

    def account_id=(value)
      @account_id = AccountId.coerce(value)
    end

    def set_account_id(value) = (self.account_id = value; self)

    def validate_query!
      raise Error, "an AccountInfoQuery needs an account_id" if @account_id.nil?
    end

    def validate_checksums(ledger_id) = @account_id&.validate_checksum!(ledger_id)

    def build_query(header)
      ::Proto::Query.new(
        cryptoGetInfo: ::Proto::CryptoGetInfoQuery.new(
          header: header,
          accountID: ::Proto::AccountID.new(shardNum: @account_id.shard,
                                            realmNum: @account_id.realm,
                                            accountNum: @account_id.num)
        )
      )
    end

    def call(channel, request, deadline:)
      channel.crypto.get_account_info(request, deadline: deadline)
    end

    def response_header(response) = response.cryptoGetInfo.header

    def map_response(response, _node_account_id, _request)
      AccountInfo.from_protobuf(response.cryptoGetInfo.accountInfo)
    end
  end
end
