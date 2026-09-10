# frozen_string_literal: true

RSpec.describe Hiero::Account::AccountBalanceQuery do
  describe "building the request" do
    it "asks for an account" do
      request = described_class.new(account_id: "1.2.3").make_request
      body = request.cryptogetAccountBalance

      expect(body.accountID.shardNum).to eq(1)
      expect(body.accountID.realmNum).to eq(2)
      expect(body.accountID.accountNum).to eq(3)
      expect(body.header.responseType).to eq(:ANSWER_ONLY)
    end

    it "asks for a contract instead" do
      body = described_class.new(contract_id: "0.0.9").make_request.cryptogetAccountBalance

      expect(body.contractID.contractNum).to eq(9)
      expect(body.accountID).to be_nil
    end

    it "treats account and contract as alternatives" do
      query = described_class.new(account_id: "0.0.1")
      query.contract_id = "0.0.2"

      expect(query.account_id).to be_nil
      expect(query.contract_id).to eq(Hiero::ContractId.new(num: 2))
    end

    it "coerces identifiers" do
      expect(described_class.new(account_id: 3).account_id).to eq(Hiero::AccountId.new(num: 3))
    end

    it "chains through set_ methods" do
      query = described_class.new.set_account_id("0.0.5")

      expect(query).to be_a(described_class)
      expect(query.account_id).to eq(Hiero::AccountId.new(num: 5))
    end
  end

  it "is free, so it needs no payment" do
    # Which is exactly why it is the first query implemented: it exercises node
    # selection, retries, deadlines and the protobuf round-trip without also
    # needing payment and signing.
    expect(described_class.new(account_id: 1).payment_required?).to be(false)
  end

  it "requires something to look up" do
    client = Hiero::Client.for_network({ "a:1" => "0.0.3" })

    expect { described_class.new.execute(client) }
      .to raise_error(Hiero::Error, /needs an account_id or a contract_id/)
  end

  describe "checksum validation" do
    let(:client) do
      Hiero::Client.for_network({ "a:1" => "0.0.3" }, ledger_id: :mainnet, auto_validate_checksums: true)
    end

    it "rejects an identifier from another network when asked to check" do
      query = described_class.new(account_id: "0.0.123-esxsf") # testnet checksum

      expect { query.execute(client) }.to raise_error(Hiero::BadEntityIdError, /different network/)
    end

    it "accepts a matching one" do
      query = described_class.new(account_id: "0.0.123-vfmkw")

      expect { query.before_execute(client) }.not_to raise_error
    end

    it "does not check unless asked" do
      lax = Hiero::Client.for_network({ "a:1" => "0.0.3" }, ledger_id: :mainnet)

      expect { described_class.new(account_id: "0.0.123-esxsf").before_execute(lax) }.not_to raise_error
    end
  end

  describe "mapping the response" do
    let(:response) do
      Proto::Response.new(
        cryptogetAccountBalance: Proto::CryptoGetAccountBalanceResponse.new(
          header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: :OK),
          accountID: Proto::AccountID.new(shardNum: 0, realmNum: 0, accountNum: 1001),
          balance: 250_000_000,
          tokenBalances: [
            Proto::TokenBalance.new(tokenId: Proto::TokenID.new(tokenNum: 77), balance: 42)
          ]
        )
      )
    end

    it "returns an AccountBalance" do
      balance = described_class.new(account_id: 1001).map_response(response, nil, nil)

      expect(balance.account_id).to eq(Hiero::AccountId.new(num: 1001))
      expect(balance.hbars).to eq(Hiero::Hbar.from_tinybars(250_000_000))
    end

    it "carries token balances, looked up by token id" do
      balance = described_class.new(account_id: 1001).map_response(response, nil, nil)

      expect(balance["0.0.77"]).to eq(42)
      expect(balance[Hiero::TokenId.new(num: 77)]).to eq(42)
      expect(balance["0.0.99"]).to be_nil
    end

    it "reads the precheck status out of the nested header" do
      query = described_class.new(account_id: 1001)

      expect(query.execution_state(nil, response)).to eq([Hiero::Status::OK, :finished])
    end

    it "retries on BUSY and fails on anything else" do
      %i[BUSY PLATFORM_NOT_ACTIVE INVALID_NODE_ACCOUNT].each do |code|
        expect(state_for(code)).to eq(:retry), code.to_s
      end

      expect(state_for(:INVALID_ACCOUNT_ID)).to eq(:error)
    end

    def state_for(code)
      response = Proto::Response.new(
        cryptogetAccountBalance: Proto::CryptoGetAccountBalanceResponse.new(
          header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: code)
        )
      )
      described_class.new(account_id: 1).execution_state(nil, response).last
    end
  end
end
