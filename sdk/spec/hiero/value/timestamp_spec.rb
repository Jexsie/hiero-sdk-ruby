# frozen_string_literal: true

RSpec.describe Hiero::Timestamp do
  let(:timestamp) { described_class.new(seconds: 1_724_764_800, nanos: 123_456_789) }

  it "keeps nanosecond precision" do
    expect(timestamp.to_s).to eq("1724764800.123456789")
    expect(timestamp.to_nanos).to eq(1_724_764_800_123_456_789)
  end

  it "round-trips through Time without losing nanoseconds" do
    # A Float cannot hold this; Time can, via Rational.
    expect(described_class.from_time(timestamp.to_time)).to eq(timestamp)
  end

  it "normalises nanoseconds that overflow a second" do
    expect(described_class.new(seconds: 0, nanos: 2_500_000_000))
      .to eq(described_class.new(seconds: 2, nanos: 500_000_000))
  end

  it "orders by seconds then nanoseconds" do
    expect(timestamp.succ).to be > timestamp
    expect([timestamp.succ, timestamp].sort).to eq([timestamp, timestamp.succ])
  end

  it "advances by a single nanosecond, which is how transaction ids are made unique" do
    expect(timestamp.succ.to_nanos - timestamp.to_nanos).to eq(1)
  end

  it "adds and subtracts durations" do
    day = Hiero::Duration.from_days(1)

    expect((timestamp + day).seconds - timestamp.seconds).to eq(86_400)
    expect((timestamp + day) - day).to eq(timestamp)
  end

  it "subtracts two timestamps into a duration" do
    expect(timestamp.succ - timestamp).to be_a(Hiero::Duration)
  end

  it "coerces from Time and Integer" do
    now = Time.now

    expect(described_class.coerce(now)).to eq(described_class.from_time(now))
    expect(described_class.coerce(5)).to eq(described_class.new(seconds: 5))
    expect(described_class.coerce(nil)).to be_nil
  end

  it "hashes by value" do
    expect({ timestamp => :ok }[described_class.new(seconds: 1_724_764_800, nanos: 123_456_789)]).to eq(:ok)
  end

  it "is immutable" do
    expect(timestamp).to be_frozen
  end
end

RSpec.describe Hiero::Duration do
  it "builds from several units" do
    expect(described_class.from_minutes(2).to_i).to eq(120)
    expect(described_class.from_hours(1).to_i).to eq(3_600)
    expect(described_class.from_days(90).to_i).to eq(7_776_000)
  end

  it "coerces from an Integer or anything with #to_i" do
    # ActiveSupport::Duration satisfies this without being depended on.
    expect(described_class.coerce(60)).to eq(described_class.new(60))
    expect(described_class.coerce(described_class.new(60))).to eq(described_class.new(60))
    expect(described_class.coerce(nil)).to be_nil
  end

  it "compares and sorts" do
    expect(described_class.new(60)).to be > described_class.new(30)
  end

  it "is immutable" do
    expect(described_class.new(1)).to be_frozen
  end
end
