# frozen_string_literal: true

RSpec.describe Hiero::AccountInfoQuery do
  it "costs money, unlike the balance query" do
    # AccountBalanceQuery is free and reads the balance alone; this one reads
    # everything and is charged for.
    expect(described_class.new(account_id: 2).payment_required?).to be(true)
  end

  it "needs an account" do
    client = Hiero::Client.for_network({ "a:1" => "0.0.3" })

    expect { described_class.new.execute(client) }.to raise_error(Hiero::Error, /needs an account_id/)
  end

  it "coerces the account" do
    expect(described_class.new(account_id: 2).account_id).to eq(Hiero::AccountId.new(num: 2))
  end

  it "asks for the account it was given" do
    query = described_class.new(account_id: "1.2.3")
    body = query.build_query(Proto::QueryHeader.new).cryptoGetInfo

    expect([body.accountID.shardNum, body.accountID.realmNum, body.accountID.accountNum]).to eq([1, 2, 3])
  end

  describe "mapping the response" do
    let(:key) { Hiero::PrivateKey.generate_ed25519.public_key }

    let(:response) do
      Proto::Response.new(
        cryptoGetInfo: Proto::CryptoGetInfoResponse.new(
          header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: :OK),
          accountInfo: Proto::CryptoGetInfoResponse::AccountInfo.new(
            accountID: Proto::AccountID.new(accountNum: 1001),
            contractAccountID: "00000000000000000000000000000000000003e9",
            key: Proto::Key.new(ed25519: key.to_bytes_raw),
            balance: 250_000_000,
            memo: "a memo",
            ownedNfts: 3,
            autoRenewPeriod: Proto::Duration.new(seconds: 7_776_000),
            receiverSigRequired: true
          )
        )
      )
    end

    subject(:info) { described_class.new(account_id: 1001).map_response(response, nil, nil) }

    it "reads the identity and balance" do
      expect(info.account_id).to eq(Hiero::AccountId.new(num: 1001))
      expect(info.balance).to eq(Hiero::Hbar.from_tinybars(250_000_000))
    end

    it "reconstructs the account's key" do
      expect(info.key).to eq(key)
    end

    it "reads the rest" do
      expect(info.memo).to eq("a memo")
      expect(info.owned_nfts).to eq(3)
      expect(info.auto_renew_period).to eq(Hiero::Duration.from_days(90))
      expect(info).to be_receiver_signature_required
      expect(info).not_to be_deleted
    end

    it "surfaces the long-zero EVM form contracts address it by" do
      expect(info.contract_account_id).to eq("00000000000000000000000000000000000003e9")
    end

    it "is immutable" do
      expect(info).to be_frozen
    end
  end

  it "reads an ECDSA account key too" do
    ecdsa = Hiero::PrivateKey.generate_ecdsa.public_key
    proto = Proto::CryptoGetInfoResponse::AccountInfo.new(
      accountID: Proto::AccountID.new(accountNum: 1),
      key: Proto::Key.new(ECDSA_secp256k1: ecdsa.to_bytes_raw),
      balance: 0
    )

    expect(Hiero::AccountInfo.from_protobuf(proto).key).to eq(ecdsa)
  end
end
