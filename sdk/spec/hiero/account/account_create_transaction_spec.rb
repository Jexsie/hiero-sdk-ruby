# frozen_string_literal: true

RSpec.describe Hiero::AccountCreateTransaction do
  let(:key) { Hiero::PrivateKey.generate_ed25519.public_key }

  it "declares the protobuf oneof it fills" do
    expect(described_class.data_case).to eq(:cryptoCreateAccount)
  end

  it "needs a key for the new account" do
    client = Hiero::Client.for_network({ "a:1" => "0.0.3" })
                          .set_operator("0.0.2", Hiero::PrivateKey.generate_ed25519)

    expect { described_class.new.execute(client) }.to raise_error(Hiero::Error, /needs a key/)
  end

  it "rejects anything that is not a Key" do
    expect { described_class.new(key: "0.0.5") }.to raise_error(ArgumentError, /must be a Hiero::Key/)
  end

  it "accepts a key list, so an account can need several signatures from birth" do
    list = Hiero::KeyList.with_threshold(2, key, Hiero::PrivateKey.generate_ecdsa.public_key)
    body = described_class.new(key: list).make_transaction_data

    expect(body.key.thresholdKey.threshold).to eq(2)
  end

  it "defaults to an empty balance" do
    expect(described_class.new(key: key).initial_balance).to eq(Hiero::Hbar::ZERO)
  end

  it "refuses a negative initial balance" do
    expect { described_class.new(key: key, initial_balance: Hiero::Hbar.new(-1)) }
      .to raise_error(ArgumentError, /cannot be negative/)
  end

  it "uses the network's own auto-renew default" do
    expect(described_class.new(key: key).auto_renew_period).to eq(Hiero::Duration.from_days(90))
  end

  describe "the protobuf body" do
    subject(:body) do
      described_class.new(key: key, initial_balance: Hiero::Hbar.new(5))
                     .set_account_memo("a memo")
                     .set_max_automatic_token_associations(3)
                     .set_receiver_signature_required(true)
                     .make_transaction_data
    end

    it "carries the key" do
      expect(Hiero::Key.from_protobuf_key(body.key)).to eq(key)
    end

    it "carries the balance in tinybars" do
      expect(body.initialBalance).to eq(500_000_000)
    end

    it "carries the rest" do
      expect(body.memo).to eq("a memo")
      expect(body.max_automatic_token_associations).to eq(3)
      expect(body.receiverSigRequired).to be(true)
    end
  end

  it "refuses every setter once frozen" do
    tx = described_class.new(key: key)
    tx.transaction_id = Hiero::TransactionId.generate("0.0.2")
    tx.node_account_ids = ["0.0.3"]
    tx.freeze_with(nil)

    expect { tx.key = key }.to raise_error(Hiero::TransactionFrozenError)
    expect { tx.initial_balance = 1 }.to raise_error(Hiero::TransactionFrozenError)
  end

  it "round-trips through bytes" do
    tx = described_class.new(key: key, initial_balance: Hiero::Hbar.new(7))
    tx.set_account_memo("round trip")
    tx.transaction_id = Hiero::TransactionId.generate("0.0.2")
    tx.node_account_ids = ["0.0.3"]
    tx.freeze_with(nil)

    restored = Hiero::Transaction.from_bytes(tx.to_bytes)

    expect(restored).to be_a(described_class)
    expect(restored.key).to eq(key)
    expect(restored.initial_balance).to eq(Hiero::Hbar.new(7))
    expect(restored.account_memo).to eq("round trip")
  end
end
