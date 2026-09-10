# frozen_string_literal: true

RSpec.describe Hiero::Client do
  let(:key) { Hiero::PrivateKey.generate_ed25519 }

  def build(**options) = described_class.for_network({ "localhost:50211" => "0.0.3" }, **options)

  describe "construction" do
    it "builds from an explicit node map" do
      expect(build.network.account_ids.map(&:to_s)).to eq(["0.0.3"])
    end

    it "knows the public networks and their ledgers" do
      expect(described_class.for_mainnet.ledger_id).to eq(Hiero::LedgerId::MAINNET)
      expect(described_class.for_testnet.ledger_id).to eq(Hiero::LedgerId::TESTNET)
      expect(described_class.for_previewnet.ledger_id).to eq(Hiero::LedgerId::PREVIEWNET)
    end

    it "dispatches by name" do
      expect(described_class.for_name("testnet").ledger_id).to eq(Hiero::LedgerId::TESTNET)
      expect { described_class.for_name("nope") }.to raise_error(ArgumentError, /unknown network/)
    end

    it "coerces node account ids" do
      client = described_class.for_network({ "a:1" => 3 })

      expect(client.network.account_ids).to eq([Hiero::AccountId.new(num: 3)])
    end
  end

  describe "defaults" do
    it "uses seconds, not milliseconds" do
      # The JavaScript SDK uses milliseconds here; mixing the two silently turns a
      # two-minute budget into two minutes of milliseconds.
      client = build

      expect(client.request_timeout).to eq(120.0)
      expect(client.grpc_deadline).to eq(10.0)
      expect(client.min_backoff).to eq(0.25)
    end

    it "allows 1 hbar of query payment" do
      expect(build.max_query_payment).to eq(Hiero::Hbar.new(1))
    end

    it "raises the attempt budget on a local network" do
      # A local node answers instantly or not at all, so a large budget is free.
      expect(build.max_attempts).to eq(10)
      expect(build(local: true).max_attempts).to eq(described_class::LOCAL_MAX_ATTEMPTS)
    end

    it "accepts overrides at construction" do
      expect(build(request_timeout: 5.0, max_attempts: 2).request_timeout).to eq(5.0)
    end

    it "does not validate checksums unless asked" do
      expect(build.auto_validate_checksums).to be(false)
    end
  end

  describe "the operator" do
    it "is set from a local key" do
      client = build.set_operator("0.0.1001", key)

      expect(client.operator_account_id).to eq(Hiero::AccountId.new(num: 1001))
    end

    it "can sign remotely instead" do
      client = build.set_operator_with("0.0.1001", key.public_key) { |bytes| key.sign(bytes) }

      expect(client.operator.public_key.verify(client.operator.sign("x"), "x")).to be(true)
    end

    it "is absent by default" do
      expect(build.operator_account_id).to be_nil
    end
  end

  describe "lifecycle" do
    it "closes idempotently" do
      client = build
      2.times { client.close }

      expect(client).to be_closed
    end

    it "refuses use after closing" do
      client = build
      client.close

      expect { client.ensure_open! }.to raise_error(Hiero::ClientClosedError)
    end

    it "closes automatically in block form" do
      # A Client owns gRPC connections; forgetting to close one keeps a script
      # from exiting. The block form makes that structurally impossible.
      captured = described_class.open(network: { "a:1" => "0.0.3" }) { |c| c }

      expect(captured).to be_closed
    end

    it "returns the client when open is called without a block" do
      client = described_class.open(network: { "a:1" => "0.0.3" })

      expect(client).not_to be_closed
      client.close
    end

    it "closes even when the block raises" do
      client = nil
      expect do
        described_class.open(network: { "a:1" => "0.0.3" }) { |c| client = c; raise "boom" }
      end.to raise_error("boom")

      expect(client).to be_closed
    end
  end

  it "can have its network replaced" do
    client = build
    client.network = { "b:2" => "0.0.4" }

    expect(client.network.account_ids.map(&:to_s)).to eq(["0.0.4"])
  end
end
