# frozen_string_literal: true

module Hiero
  # An amount of hbar.
  #
  # Stored as an integer number of tinybars, the smallest unit the network
  # recognises. Ruby integers are arbitrary-precision, so this is exact at any
  # magnitude with no decimal or big-number library involved -- the JavaScript SDK
  # needs BigNumber here purely because its numbers are floats.
  #
  # Fractional tinybars are rejected rather than rounded. Silently losing a
  # fraction of a unit is how money bugs start, and there is no correct rounding
  # direction to pick on someone else's behalf.
  class Hbar
    include Comparable

    TINYBARS_PER_HBAR = 100_000_000

    # Every unit the network and its tooling use, in tinybars.
    UNITS = {
      tinybar:  1,
      microbar: 100,
      millibar: 100_000,
      hbar:     TINYBARS_PER_HBAR,
      kilobar:  TINYBARS_PER_HBAR * 1_000,
      megabar:  TINYBARS_PER_HBAR * 1_000_000,
      gigabar:  TINYBARS_PER_HBAR * 1_000_000_000
    }.freeze

    SYMBOLS = {
      tinybar: "tℏ", microbar: "μℏ", millibar: "mℏ", hbar: "ℏ",
      kilobar: "kℏ", megabar: "Mℏ", gigabar: "Gℏ"
    }.freeze

    attr_reader :tinybars

    # @param amount [Integer, Rational, BigDecimal] an amount in whole hbar
    def initialize(amount = 0, unit: :hbar)
      @tinybars = self.class.to_tinybars(amount, unit)
      freeze
    end

    class << self
      def from_tinybars(tinybars) = new(Integer(tinybars), unit: :tinybar)

      def from(amount, unit) = new(amount, unit: unit)

      ZERO = nil # replaced below, once the class is fully defined

      def to_tinybars(amount, unit)
        factor = UNITS.fetch(unit) { raise ArgumentError, "unknown unit #{unit.inspect}" }
        exact = Rational(amount) * factor

        unless exact.denominator == 1
          raise ArgumentError,
                "#{amount} #{unit} is #{exact.to_f} tinybars, which is not a whole number. " \
                "Tinybars are indivisible; round explicitly if that is what you intend."
        end

        exact.numerator
      end
    end

    def to_tinybars = @tinybars

    # @return [Rational] the amount in `unit`, exact rather than rounded
    def to(unit)
      factor = UNITS.fetch(unit) { raise ArgumentError, "unknown unit #{unit.inspect}" }
      Rational(@tinybars, factor)
    end

    def to_hbar = to(:hbar)

    def +(other) = self.class.from_tinybars(@tinybars + self.class.coerce(other).tinybars)
    def -(other) = self.class.from_tinybars(@tinybars - self.class.coerce(other).tinybars)
    def -@ = self.class.from_tinybars(-@tinybars)

    # Scaling by a plain number is meaningful -- three times a fee. Multiplying
    # two amounts of money is not, so only numerics are accepted.
    def *(factor)
      raise ArgumentError, "can only scale an Hbar by a number" unless factor.is_a?(Numeric)

      self.class.from_tinybars(self.class.to_tinybars(Rational(@tinybars) * factor, :tinybar))
    end

    def negative? = @tinybars.negative?
    def positive? = @tinybars.positive?
    def zero? = @tinybars.zero?
    def abs = self.class.from_tinybars(@tinybars.abs)

    def <=>(other)
      return nil unless other.is_a?(Hbar)

      @tinybars <=> other.tinybars
    end

    def ==(other) = other.is_a?(Hbar) && other.tinybars == @tinybars
    alias eql? ==

    def hash = [self.class, @tinybars].hash

    # Renders in the largest unit that keeps the value a whole number, so a fee of
    # 100_000 tinybars reads as "1 mℏ" rather than as a wall of digits.
    def to_s
      unit, factor = UNITS.to_a.reverse.find { |_, f| !@tinybars.zero? && (@tinybars % f).zero? } || [:tinybar, 1]
      "#{@tinybars / factor} #{SYMBOLS[unit]}"
    end

    def inspect = "#<#{self.class} #{self} (#{@tinybars} tinybars)>"

    def self.coerce(value)
      case value
      when Hbar then value
      when Integer, Rational then new(value)
      else raise ArgumentError, "cannot interpret #{value.inspect} as an Hbar"
      end
    end
  end

  # Defined after the class body so it can use the finished class.
  Hbar::ZERO = Hbar.from_tinybars(0)
  Hbar::MAX = Hbar.from_tinybars(50_000_000_000 * Hbar::TINYBARS_PER_HBAR)
  Hbar::MIN = Hbar.from_tinybars(-50_000_000_000 * Hbar::TINYBARS_PER_HBAR)
end
