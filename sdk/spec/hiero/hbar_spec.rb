# frozen_string_literal: true

RSpec.describe Hiero::Hbar do
  it "stores whole hbar as tinybars" do
    expect(described_class.new(1).to_tinybars).to eq(100_000_000)
  end

  it "converts between every unit" do
    expect(described_class.from(1, :kilobar).to_tinybars).to eq(100_000_000_000)
    expect(described_class.from_tinybars(100).to(:microbar)).to eq(1)
    expect(described_class.new(1).to(:millibar)).to eq(1_000)
  end

  it "is exact at magnitudes that would break a float" do
    # Ruby integers are arbitrary-precision, so no big-number library is needed.
    huge = 2**70
    expect(described_class.from_tinybars(huge).to_tinybars).to eq(huge)
  end

  describe "fractional amounts" do
    it "refuses rather than rounding" do
      # Silently dropping a fraction of a tinybar is how money bugs start, and
      # there is no correct direction to round in on the caller's behalf.
      expect { described_class.new(Rational(1, 3)) }
        .to raise_error(ArgumentError, /not a whole number/)
    end

    it "accepts a fraction that lands on a whole tinybar" do
      expect(described_class.new(Rational(1, 8)).to_tinybars).to eq(12_500_000)
    end
  end

  describe "arithmetic" do
    it "adds and subtracts" do
      expect(described_class.new(5) + described_class.new(2)).to eq(described_class.new(7))
      expect(described_class.new(5) - described_class.new(7)).to eq(described_class.new(-2))
    end

    it "negates" do
      expect(-described_class.new(3)).to eq(described_class.new(-3))
    end

    it "scales by a number" do
      expect(described_class.new(2) * 3).to eq(described_class.new(6))
      expect(described_class.new(1) * Rational(1, 2)).to eq(described_class.from_tinybars(50_000_000))
    end

    it "refuses to multiply two amounts of money, which means nothing" do
      expect { described_class.new(2) * described_class.new(3) }
        .to raise_error(ArgumentError, /only scale an Hbar by a number/)
    end
  end

  describe "comparison" do
    it "orders by tinybars" do
      expect(described_class.new(1)).to be > described_class.from_tinybars(99_999_999)
      expect([described_class.new(2), described_class.new(1)].sort.first).to eq(described_class.new(1))
    end

    it "does not compare against bare numbers" do
      expect(described_class.new(1) <=> 1).to be_nil
    end

    it "hashes by value" do
      expect({ described_class.new(1) => :ok }[described_class.from_tinybars(100_000_000)]).to eq(:ok)
    end
  end

  describe "predicates" do
    it "reports sign" do
      expect(described_class.new(-1)).to be_negative
      expect(described_class.new(1)).to be_positive
      expect(described_class::ZERO).to be_zero
    end

    it "takes an absolute value" do
      expect(described_class.new(-5).abs).to eq(described_class.new(5))
    end
  end

  it "renders in the largest unit that stays whole" do
    expect(described_class.new(1).to_s).to eq("1 ℏ")
    expect(described_class.from_tinybars(100_000).to_s).to eq("1 mℏ")
    expect(described_class.from_tinybars(1).to_s).to eq("1 tℏ")
    expect(described_class.from_tinybars(150_000_000).to_s).to eq("1500 mℏ") # 1.5 hbar
    expect(described_class::ZERO.to_s).to eq("0 tℏ")
  end

  it "rejects an unknown unit" do
    expect { described_class.new(1, unit: :dogecoin) }.to raise_error(ArgumentError, /unknown unit/)
  end

  it "is immutable" do
    expect(described_class.new(1)).to be_frozen
  end
end
