# frozen_string_literal: true

RSpec.describe Hiero::Network::Node do
  subject(:node) { described_class.new(address: "localhost:50211", account_id: "0.0.3") }

  it "starts healthy" do
    expect(node).to be_healthy
    expect(node.backoff).to eq(described_class::MIN_BACKOFF)
  end

  it "coerces its account id" do
    expect(node.account_id).to eq(Hiero::AccountId.new(num: 3))
  end

  describe "backoff" do
    it "stands the node down for the current backoff after a failure" do
      now = Hiero::Clock.now
      node.increase_backoff!(now)

      expect(node.healthy?(now)).to be(false)
      expect(node.healthy?(now + described_class::MIN_BACKOFF)).to be(true)
    end

    it "doubles on each consecutive failure" do
      backoffs = 4.times.map { node.increase_backoff!.backoff }

      expect(backoffs).to eq([16.0, 32.0, 64.0, 128.0])
    end

    it "stops doubling at the ceiling" do
      node = described_class.new(address: "a:1", account_id: 3, min_backoff: 1.0, max_backoff: 4.0)
      10.times { node.increase_backoff! }

      expect(node.backoff).to eq(4.0)
    end

    it "halves on success rather than resetting" do
      # A node flapping between working and failing should not have its penalty
      # wiped by every success, or the backoff would never grow past step one.
      3.times { node.increase_backoff! }
      expect(node.backoff).to eq(64.0)

      node.decrease_backoff!
      expect(node.backoff).to eq(32.0)
    end

    it "never falls below the floor" do
      10.times { node.decrease_backoff! }

      expect(node.backoff).to eq(described_class::MIN_BACKOFF)
    end

    it "readmits immediately on success" do
      node.increase_backoff!
      expect(node).not_to be_healthy

      node.decrease_backoff!
      expect(node).to be_healthy
    end
  end

  describe "eviction" do
    it "is never dead when max_attempts is negative, which is the default" do
      # A node is far more often briefly unreachable than actually gone, and
      # evicting it permanently cannot be undone without a restart.
      50.times { node.increase_backoff! }

      expect(node.dead?(-1)).to be(false)
    end

    it "is dead once the failure count reaches an opted-in limit" do
      2.times { node.increase_backoff! }

      expect(node.dead?(3)).to be(false)
      expect(node.dead?(2)).to be(true)
    end
  end

  it "counts uses" do
    3.times { node.record_use! }

    expect(node.use_count).to eq(3)
  end

  it "is safe to mutate from several threads" do
    # A Client is shared across a whole process, so health bookkeeping is
    # genuinely concurrent.
    threads = 8.times.map { Thread.new { 50.times { node.record_use! } } }
    threads.each(&:join)

    expect(node.use_count).to eq(400)
  end
end
