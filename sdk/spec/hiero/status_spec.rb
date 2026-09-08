# frozen_string_literal: true

RSpec.describe Hiero::Status do
  it "defines every code the protocol has" do
    expect(described_class.all.length).to be > 300
  end

  it "exposes codes as constants and singletons" do
    expect(described_class::SUCCESS.code).to eq(22)
    expect(described_class[22]).to be(described_class::SUCCESS)
  end

  it "distinguishes OK from SUCCESS" do
    # OK means a node accepted the transaction for processing. It says nothing
    # about whether it succeeded, and treating it as success is a real bug.
    expect(described_class::OK).not_to be_success
    expect(described_class::SUCCESS).to be_success
  end

  it "returns an unknown code rather than raising" do
    # A node speaking a newer protocol must not break an older client.
    unknown = described_class[99_999]

    expect(unknown.code).to eq(99_999)
    expect(unknown).not_to be_known
    expect(unknown.to_s).to eq("UNKNOWN_STATUS_99999")
  end

  it "prints its name" do
    expect(described_class::SUCCESS.to_s).to eq("SUCCESS")
    expect("#{described_class::INVALID_SIGNATURE}").to eq("INVALID_SIGNATURE")
  end

  it "works in case/when and as a Hash key" do
    expect({ described_class::SUCCESS => :ok }[described_class[22]]).to eq(:ok)

    matched = case described_class[7]
              when described_class::INVALID_SIGNATURE then :signature
              end
    expect(matched).to eq(:signature)
  end

  it "cannot be instantiated outside the generated table" do
    expect { described_class.new(1, :NOPE) }.to raise_error(NoMethodError)
  end

  it "is immutable" do
    expect(described_class::SUCCESS).to be_frozen
  end
end
