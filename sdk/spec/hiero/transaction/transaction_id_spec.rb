# frozen_string_literal: true

RSpec.describe Hiero::TransactionId do
  let(:id) do
    described_class.new(account_id: "0.0.1001",
                        valid_start: Hiero::Timestamp.new(seconds: 1_700_000_000, nanos: 123))
  end

  it "renders as payer@validStart" do
    expect(id.to_s).to eq("0.0.1001@1700000000.000000123")
  end

  it "round-trips through a string" do
    expect(described_class.from_string(id.to_s)).to eq(id)
  end

  it "round-trips through protobuf" do
    Hiero.protobuf!

    expect(described_class.from_protobuf(id.to_protobuf)).to eq(id)
  end

  describe ".generate" do
    it "places the valid start slightly in the past" do
      # A node rejects a transaction whose start is in its future, and client and
      # node clocks differ by more than most people expect.
      generated = described_class.generate("0.0.1001")

      expect(generated.valid_start.seconds).to be <= Time.now.to_i
      expect(Time.now.to_i - generated.valid_start.seconds).to be <= described_class::CLOCK_SKEW + 1
    end

    it "coerces the payer" do
      expect(described_class.generate(1001).account_id).to eq(Hiero::AccountId.new(num: 1001))
    end
  end

  describe "#succ" do
    it "advances one nanosecond" do
      expect(id.succ.valid_start.to_nanos - id.valid_start.to_nanos).to eq(1)
    end

    it "differs from the original, so the network sees two transactions not a duplicate" do
      expect(id.succ).not_to eq(id)
    end

    it "keeps the payer" do
      expect(id.succ.account_id).to eq(id.account_id)
    end
  end

  it "rejects malformed strings" do
    ["0.0.1001", "@1700000000.0", "0.0.1001@", "nonsense"].each do |bad|
      expect { described_class.from_string(bad) }.to raise_error(ArgumentError), bad.inspect
    end
  end

  it "orders by payer then valid start" do
    expect(id.succ).to be > id
  end

  it "hashes by value, so duplicate detection can use it as a key" do
    twin = described_class.new(account_id: "0.0.1001",
                               valid_start: Hiero::Timestamp.new(seconds: 1_700_000_000, nanos: 123))

    expect({ id => :ok }[twin]).to eq(:ok)
  end

  it "is immutable" do
    expect(id).to be_frozen
  end
end
