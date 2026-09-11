# frozen_string_literal: true

RSpec.describe Hiero::Account::TransferTransaction do
  it "balances when debits and credits match" do
    tx = described_class.new
         .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))
         .add_hbar_transfer("0.0.1002", Hiero::Hbar.new(1))

    expect(tx).to be_balanced
    expect(tx.imbalance).to eq(Hiero::Hbar::ZERO)
  end

  it "reports which way an unbalanced transfer is out" do
    # The network rejects these, so catching it here means the error can say
    # something useful instead of surfacing as a precheck failure.
    tx = described_class.new.add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))

    expect(tx.imbalance).to eq(Hiero::Hbar.new(-1))
    expect { tx.validate_balanced! }.to raise_error(Hiero::Error, /out by -1/)
  end

  it "accumulates repeated transfers to one account" do
    # Two credits to the same account are one net credit, which is what the
    # network expects to see.
    tx = described_class.new
         .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))
         .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-2))

    expect(tx.hbar_transfers[Hiero::AccountId.new(num: 1001)]).to eq(Hiero::Hbar.new(-3))
    expect(tx.hbar_transfers.size).to eq(1)
  end

  it "coerces accounts and amounts" do
    tx = described_class.new.add_hbar_transfer(1001, Hiero::Hbar.new(-1))

    expect(tx.hbar_transfers.keys).to eq([Hiero::AccountId.new(num: 1001)])
  end

  it "takes transfers in the constructor" do
    tx = described_class.new(hbar_transfers: { "0.0.1" => Hiero::Hbar.new(-1), "0.0.2" => Hiero::Hbar.new(1) })

    expect(tx).to be_balanced
  end

  it "declares the protobuf oneof it fills" do
    expect(described_class.data_case).to eq(:cryptoTransfer)
  end

  describe "the protobuf body" do
    it "carries every transfer as a signed tinybar amount" do
      tx = described_class.new
           .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))
           .add_hbar_transfer("0.0.1002", Hiero::Hbar.new(1))

      amounts = tx.make_transaction_data.transfers.accountAmounts

      expect(amounts.map(&:amount)).to eq([-100_000_000, 100_000_000])
      expect(amounts.map { |a| a.accountID.accountNum }).to eq([1001, 1002])
    end
  end

  describe "validation before sending" do
    let(:client) do
      Hiero::Client.for_network({ "a:1" => "0.0.3" })
                   .set_operator("0.0.1001", Hiero::PrivateKey.generate_ed25519)
    end

    it "refuses an empty transfer" do
      expect { described_class.new.execute(client) }
        .to raise_error(Hiero::Error, /at least one transfer/)
    end

    it "refuses an unbalanced one before it reaches the network" do
      tx = described_class.new.add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))

      expect { tx.execute(client) }.to raise_error(Hiero::Error, /sum to zero/)
    end
  end

  it "round-trips through bytes" do
    tx = described_class.new
         .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-5))
         .add_hbar_transfer("0.0.1002", Hiero::Hbar.new(5))
    tx.transaction_id = Hiero::TransactionId.generate("0.0.1001")
    tx.node_account_ids = ["0.0.3"]
    tx.freeze_with(nil)

    restored = Hiero::Transaction.from_bytes(tx.to_bytes)

    expect(restored.hbar_transfers).to eq(tx.hbar_transfers)
  end
end
