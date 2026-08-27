# frozen_string_literal: true

RSpec.describe Hiero::KeyList do
  let(:alice) { Hiero::PrivateKey.generate_ed25519.public_key }
  let(:bob)   { Hiero::PrivateKey.generate_ecdsa.public_key }

  it "collects keys" do
    list = described_class.of(alice, bob)

    expect(list.size).to eq(2)
    expect(list.to_a).to eq([alice, bob])
  end

  it "is Enumerable" do
    list = described_class.of(alice, bob)

    expect(list.map(&:algorithm)).to eq(%i[ed25519 ecdsa])
    expect(list.select(&:ecdsa?)).to eq([bob])
  end

  it "appends with << " do
    list = described_class.new
    list << alice << bob

    expect(list.size).to eq(2)
  end

  describe "thresholds" do
    it "has none by default, meaning every key must sign" do
      expect(described_class.of(alice, bob)).not_to be_threshold
    end

    it "records one when given" do
      list = described_class.with_threshold(1, alice, bob)

      expect(list).to be_threshold
      expect(list.threshold).to eq(1)
    end

    it "rejects a non-positive threshold" do
      expect { described_class.new([alice], threshold: 0) }.to raise_error(ArgumentError, /positive/)
    end
  end

  it "nests, so a member may itself be a list" do
    inner = described_class.with_threshold(1, alice, bob)
    outer = described_class.of(alice, inner)

    expect(outer.size).to eq(2)
    expect(outer.to_a.last).to be_a(described_class)
  end

  it "rejects anything that is not a Key" do
    expect { described_class.of("0.0.1234") }.to raise_error(ArgumentError, /expected a Hiero::Key/)
    expect { described_class.of(Hiero::PrivateKey.generate) }.to raise_error(ArgumentError, /expected a Hiero::Key/)
  end

  it "compares by contents and threshold" do
    expect(described_class.of(alice, bob)).to eq(described_class.of(alice, bob))
    expect(described_class.of(alice, bob)).not_to eq(described_class.with_threshold(1, alice, bob))
    expect(described_class.of(alice, bob)).not_to eq(described_class.of(bob, alice))
  end

  it "is a Key, so lists nest and can be used wherever a key is expected" do
    expect(described_class.new).to be_a(Hiero::Key)
  end
end
