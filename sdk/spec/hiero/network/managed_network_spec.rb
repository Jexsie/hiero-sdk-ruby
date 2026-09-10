# frozen_string_literal: true

RSpec.describe Hiero::Network::ManagedNetwork do
  subject(:network) { described_class.new }

  let(:addresses) { { "a:1" => "0.0.3", "b:2" => "0.0.4", "c:3" => "0.0.5" } }

  before { network.replace(addresses) }

  it "holds a node per address" do
    expect(network.nodes.map(&:to_s)).to contain_exactly("0.0.3@a:1", "0.0.4@b:2", "0.0.5@c:3")
  end

  it "replaces the pool wholesale, so nodes removed upstream disappear" do
    network.replace({ "z:9" => "0.0.9" })

    expect(network.account_ids.map(&:to_s)).to eq(["0.0.9"])
    expect(network).not_to include("0.0.3")
  end

  describe "#node_for" do
    it "resolves a specific account" do
      expect(network.node_for("0.0.4").account_id).to eq(Hiero::AccountId.new(num: 4))
    end

    it "returns any healthy node when given none" do
      expect(network.node_for).to be_a(Hiero::Network::Node)
    end

    it "returns nil for an account not in the network" do
      expect(network.node_for("0.0.99")).to be_nil
    end

    it "counts the use" do
      3.times { network.node_for("0.0.3") }

      expect(network.node_for("0.0.3").use_count).to eq(4)
    end

    it "picks among several addresses behind one account" do
      # A node can be reachable through more than one proxy address.
      network.replace({ "a:1" => "0.0.3", "a:2" => "0.0.3" })

      expect(20.times.map { network.node_for("0.0.3").address }.uniq).to contain_exactly("a:1", "a:2")
    end

    it "still returns a node pinned to an account even when that node is unhealthy" do
      # The caller asked for this account specifically -- a transaction signed for
      # it cannot be sent anywhere else -- so waiting and retrying beats failing.
      node = network.node_for("0.0.3")
      network.increase_backoff(node)

      expect(network.node_for("0.0.3")).to eq(node)
    end
  end

  describe "health" do
    it "drops an unhealthy node from the healthy pool" do
      network.increase_backoff(network.node_for("0.0.3"))

      expect(network.healthy_nodes.map(&:account_id).map(&:to_s)).to contain_exactly("0.0.4", "0.0.5")
    end

    it "restores it on success" do
      node = network.node_for("0.0.3")
      network.increase_backoff(node)
      network.decrease_backoff(node)

      expect(network.healthy_nodes.length).to eq(3)
    end

    it "never selects an unhealthy node when asked for any" do
      network.nodes.each { |n| network.increase_backoff(n) unless n.account_id.num == 4 }

      expect(20.times.map { network.node_for.account_id.num }.uniq).to eq([4])
    end
  end

  describe "#healthiest" do
    it "returns distinct accounts, sampled without replacement" do
      chosen = network.healthiest(2)

      expect(chosen.length).to eq(2)
      expect(chosen.map(&:account_id).uniq.length).to eq(2)
    end

    it "returns everything when asked for more than exists" do
      expect(network.healthiest(10).length).to eq(3)
    end

    it "prefers healthy nodes" do
      network.increase_backoff(network.node_for("0.0.3"))

      expect(network.healthiest(2).map(&:account_id).map(&:to_s)).not_to include("0.0.3")
    end

    it "falls back to the whole pool when nothing is healthy" do
      # Better to try a node that is probably down than to report no network at all.
      network.nodes.each { |n| network.increase_backoff(n) }

      expect(network.healthiest(2).length).to eq(2)
    end
  end

  describe "eviction" do
    it "keeps failing nodes by default" do
      node = network.node_for("0.0.3")
      50.times { network.increase_backoff(node) }

      expect(network.nodes.length).to eq(3)
    end

    it "removes a node once an opted-in attempt limit is reached" do
      network = described_class.new(max_node_attempts: 2)
      network.replace(addresses)
      node = network.node_for("0.0.3")

      2.times { network.increase_backoff(node) }

      expect(network.nodes.length).to eq(2)
      expect(network).not_to include("0.0.3")
    end
  end

  it "is safe to use from several threads" do
    # The lock guards membership and health only; it is never held across a call.
    results = 8.times.map do
      Thread.new do
        50.times do
          node = network.node_for
          network.increase_backoff(node)
          network.decrease_backoff(node)
        end
        :done
      end
    end.map(&:value)

    expect(results).to all(eq(:done))
    expect(network.nodes.length).to eq(3)
  end
end
