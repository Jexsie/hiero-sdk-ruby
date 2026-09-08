# frozen_string_literal: true

RSpec.describe Hiero::LedgerId do
  it "names the three public networks" do
    expect(described_class::MAINNET.to_s).to eq("mainnet")
    expect(described_class::TESTNET.to_s).to eq("testnet")
    expect(described_class::PREVIEWNET.to_s).to eq("previewnet")
  end

  it "identifies each network" do
    expect(described_class::MAINNET).to be_mainnet
    expect(described_class::TESTNET).to be_testnet
    expect(described_class::PREVIEWNET).to be_previewnet
    expect(described_class::MAINNET).not_to be_testnet
  end

  it "parses names" do
    expect(described_class.from_string("testnet")).to eq(described_class::TESTNET)
    expect(described_class.from_string("TESTNET")).to eq(described_class::TESTNET)
  end

  it "coerces symbols, strings and itself" do
    expect(described_class.coerce(:mainnet)).to eq(described_class::MAINNET)
    expect(described_class.coerce("mainnet")).to eq(described_class::MAINNET)
    expect(described_class.coerce(described_class::MAINNET)).to eq(described_class::MAINNET)
    expect(described_class.coerce(nil)).to be_nil
  end

  it "represents an unrecognised ledger by its hex" do
    custom = described_class.from_string("03")

    expect(custom).not_to be_known
    expect(custom.to_s).to eq("03")
  end

  it "knows the public networks by name" do
    expect(described_class::MAINNET).to be_known
  end

  it "rejects something that is not a ledger" do
    expect { described_class.coerce(42) }.to raise_error(ArgumentError, /cannot interpret/)
  end
end
