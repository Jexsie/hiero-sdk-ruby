# frozen_string_literal: true

module Hiero
  # Everything a consensus node knows about an account.
  class AccountInfo
    attr_reader :account_id, :contract_account_id, :key, :balance, :memo,
                :expiration_time, :auto_renew_period, :owned_nfts,
                :max_automatic_token_associations, :receiver_signature_required, :deleted

    def initialize(**attributes)
      attributes.each { |name, value| instance_variable_set(:"@#{name}", value) }
      freeze
    end

    def self.from_protobuf(info)
      new(
        account_id: AccountId.new(shard: info.accountID.shardNum,
                                  realm: info.accountID.realmNum,
                                  num: info.accountID.accountNum),
        # The long-zero EVM form of the same account, which contracts address it by.
        contract_account_id: info.contractAccountID.empty? ? nil : info.contractAccountID,
        key: info.key && PublicKey.from_protobuf_key(info.key),
        balance: Hbar.from_tinybars(info.balance),
        memo: info.memo,
        expiration_time: info.expirationTime && Timestamp.new(seconds: info.expirationTime.seconds,
                                                              nanos: info.expirationTime.nanos),
        auto_renew_period: info.autoRenewPeriod && Duration.new(info.autoRenewPeriod.seconds),
        owned_nfts: info.ownedNfts,
        max_automatic_token_associations: info.max_automatic_token_associations,
        receiver_signature_required: info.receiverSigRequired,
        deleted: info.deleted
      )
    end

    def deleted? = @deleted
    def receiver_signature_required? = @receiver_signature_required

    def to_s = "#{@account_id} holding #{@balance}"
    def inspect = "#<#{self.class} #{self}#{@deleted ? ' (deleted)' : ''}>"
  end
end
