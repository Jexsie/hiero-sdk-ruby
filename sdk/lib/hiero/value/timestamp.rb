# frozen_string_literal: true

# Time#iso8601, used by #inspect, lives in the stdlib time library rather than in
# core Ruby, so it has to be required explicitly.
require "time"

module Hiero
  # A point in time, to nanosecond precision.
  #
  # Held as whole seconds plus nanoseconds rather than as a Float, because
  # consensus timestamps are compared and ordered exactly and a Float loses
  # nanosecond resolution well before it runs out of seconds. Ruby's Time can
  # represent this precisely too, via Rational, so {#to_time} is lossless -- but
  # arithmetic here stays in integers where there is nothing to lose.
  class Timestamp
    include Comparable

    NANOSECONDS_PER_SECOND = 1_000_000_000

    attr_reader :seconds, :nanos

    def initialize(seconds:, nanos: 0)
      seconds = Integer(seconds)
      nanos = Integer(nanos)

      # Normalise so that nanos is always in range and comparisons are total.
      seconds += nanos / NANOSECONDS_PER_SECOND
      nanos %= NANOSECONDS_PER_SECOND

      @seconds = seconds
      @nanos = nanos
      freeze
    end

    class << self
      def now = from_time(Time.now)

      def from_time(time)
        new(seconds: time.to_i, nanos: time.nsec)
      end

      def from_nanos(total) = new(seconds: 0, nanos: Integer(total))

      def coerce(value)
        case value
        when Timestamp then value
        when Time then from_time(value)
        when Integer then new(seconds: value)
        when nil then nil
        else raise ArgumentError, "cannot interpret #{value.inspect} as a Timestamp"
        end
      end
    end

    def to_nanos = (@seconds * NANOSECONDS_PER_SECOND) + @nanos

    # Lossless: Rational keeps the nanoseconds that a Float would discard.
    def to_time = Time.at(@seconds, Rational(@nanos, 1_000))

    def +(duration)
      seconds = duration.is_a?(Duration) ? duration.seconds : Integer(duration)
      self.class.new(seconds: @seconds + seconds, nanos: @nanos)
    end

    def -(other)
      return self.class.new(seconds: @seconds - other.seconds, nanos: @nanos) if other.is_a?(Duration)
      return Duration.new(@seconds - other.seconds) if other.is_a?(Timestamp)

      self.class.new(seconds: @seconds - Integer(other), nanos: @nanos)
    end

    # A nanosecond later. Transaction ids are made unique this way when several
    # are generated within the same nanosecond-resolution instant.
    def succ = self.class.new(seconds: @seconds, nanos: @nanos + 1)

    def <=>(other)
      return nil unless other.is_a?(Timestamp)

      [@seconds, @nanos] <=> [other.seconds, other.nanos]
    end

    def ==(other) = other.is_a?(Timestamp) && other.seconds == @seconds && other.nanos == @nanos
    alias eql? ==
    def hash = [self.class, @seconds, @nanos].hash

    def to_s = "#{@seconds}.#{@nanos.to_s.rjust(9, '0')}"
    def inspect = "#<#{self.class} #{self} (#{to_time.utc.iso8601(9)})>"
  end
end
