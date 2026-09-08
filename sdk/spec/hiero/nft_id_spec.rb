# frozen_string_literal: true

RSpec.describe Hiero::NftId do
  it "pairs a token with a serial number" do
    id = described_class.from_string("0.0.1234/7")

    expect(id.token_id).to eq(Hiero::TokenId.from_string("0.0.1234"))
    expect(id.serial).to eq(7)
    expect(id.to_s).to eq("0.0.1234/7")
  end

  it "coerces the token identifier" do
    expect(described_class.new(token_id: "0.0.5", serial: 1).token_id).to eq(Hiero::TokenId.new(num: 5))
  end

  it "rejects a non-positive serial, NFT serials starting at 1" do
    expect { described_class.new(token_id: "0.0.5", serial: 0) }.to raise_error(ArgumentError, /starts at 1/)
  end

  it "rejects malformed strings" do
    ["0.0.1234", "0.0.1234/", "/7", "0.0.1234/x"].each do |bad|
      expect { described_class.from_string(bad) }.to raise_error(Hiero::BadEntityIdError), bad.inspect
    end
  end

  it "sorts by token then serial" do
    ids = ["0.0.2/1", "0.0.1/10", "0.0.1/2"].map { |s| described_class.from_string(s) }

    expect(ids.sort.map(&:to_s)).to eq(["0.0.1/2", "0.0.1/10", "0.0.2/1"])
  end

  it "compares by value" do
    expect(described_class.from_string("0.0.1/1")).to eq(described_class.new(token_id: 1, serial: 1))
  end
end
