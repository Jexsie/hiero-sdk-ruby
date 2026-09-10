# frozen_string_literal: true

module Hiero
  module Account
    # An account's hbar balance, and its balance of each token it holds.
    class AccountBalance
      attr_reader :account_id, :hbars, :token_balances

      def initialize(account_id:, hbars:, token_balances: {})
        @account_id = account_id
        @hbars = hbars
        @token_balances = token_balances.freeze
        freeze
      end

      def self.from_protobuf(response)
        new(
          account_id: response.accountID && AccountId.new(
            shard: response.accountID.shardNum,
            realm: response.accountID.realmNum,
            num: response.accountID.accountNum
          ),
          hbars: Hbar.from_tinybars(response.balance),
          token_balances: response.tokenBalances.to_h do |entry|
            [TokenId.new(shard: entry.tokenId.shardNum,
                         realm: entry.tokenId.realmNum,
                         num: entry.tokenId.tokenNum),
             entry.balance]
          end
        )
      end

      # @param token [TokenId, String, Integer]
      # @return [Integer, nil] the balance in that token's smallest unit
      def [](token) = @token_balances[TokenId.coerce(token)]

      def to_s
        @token_balances.empty? ? @hbars.to_s : "#{@hbars} and #{@token_balances.size} token balances"
      end

      def inspect = "#<#{self.class} #{@account_id} #{self}>"
    end
  end
end
