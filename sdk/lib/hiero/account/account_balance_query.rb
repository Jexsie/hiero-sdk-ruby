# frozen_string_literal: true

module Hiero
  # Reads an account's hbar and token balances.
  #
  # Free, which is why it is the first query implemented: it exercises the whole
  # execution path -- node selection, retries, deadlines, protobuf round-trip --
  # without also needing the payment and signing machinery.
  #
  # Balances come from a consensus node and are current. The mirror node is
  # cheaper but lags by seconds, so a balance read there straight after a
  # transfer may still show the old value.
  class AccountBalanceQuery < Query
    attr_reader :account_id, :contract_id

    def initialize(account_id: nil, contract_id: nil)
      super()
      self.account_id = account_id if account_id
      self.contract_id = contract_id if contract_id
    end

    def account_id=(value)
      @account_id = AccountId.coerce(value)
      @contract_id = nil
      value
    end

    def contract_id=(value)
      @contract_id = ContractId.coerce(value)
      @account_id = nil
      value
    end

    def set_account_id(value) = (self.account_id = value; self)
    def set_contract_id(value) = (self.contract_id = value; self)

    # Free: the network does not charge for a balance lookup.
    def payment_required? = false

    def validate_query!
      raise Error, "an AccountBalanceQuery needs an account_id or a contract_id" if @account_id.nil? && @contract_id.nil?
    end

    def validate_checksums(ledger_id)
      @account_id&.validate_checksum!(ledger_id)
      @contract_id&.validate_checksum!(ledger_id)
    end

    def build_query(header)
      body = ::Proto::CryptoGetAccountBalanceQuery.new(header: header)
      if @account_id
        body.accountID = ::Proto::AccountID.new(
          shardNum: @account_id.shard, realmNum: @account_id.realm, accountNum: @account_id.num
        )
      else
        body.contractID = ::Proto::ContractID.new(
          shardNum: @contract_id.shard, realmNum: @contract_id.realm, contractNum: @contract_id.num
        )
      end

      ::Proto::Query.new(cryptogetAccountBalance: body)
    end

    # Note the snake_case. The gRPC Ruby generator renames stub methods even
    # though the service descriptor keeps the protobuf spelling, so the RPC is
    # :cryptoGetBalance in the descriptor and #crypto_get_balance here.
    def call(channel, request, deadline:)
      channel.crypto.crypto_get_balance(request, deadline: deadline)
    end

    def response_header(response) = response.cryptogetAccountBalance.header

    def map_response(response, _node_account_id, _request)
      AccountBalance.from_protobuf(response.cryptogetAccountBalance)
    end
  end
end
