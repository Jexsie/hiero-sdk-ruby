# frozen_string_literal: true

RSpec.describe Hiero::Clock do
  it "returns seconds as a Float" do
    expect(described_class.now).to be_a(Float)
  end

  it "never goes backwards" do
    # This is the whole reason it exists: the wall clock can move backwards on an
    # NTP correction, which would make a retry deadline hang or spin.
    samples = 100.times.map { described_class.now }

    expect(samples).to eq(samples.sort)
  end

  it "measures elapsed time" do
    start = described_class.now
    sleep 0.01

    expect(described_class.now - start).to be >= 0.01
  end
end
