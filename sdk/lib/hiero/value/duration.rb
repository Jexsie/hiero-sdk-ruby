# frozen_string_literal: true

module Hiero
  # A length of time, in whole seconds.
  #
  # The network measures durations in seconds, so that is what this stores. Note
  # that the SDK's own timeouts are plain Ruby Floats in seconds; this type is for
  # durations that travel to the network, such as an account's auto-renew period.
  class Duration
    include Comparable

    attr_reader :seconds

    def initialize(seconds)
      @seconds = Integer(seconds)
      freeze
    end

    class << self
      def from_seconds(seconds) = new(seconds)
      def from_minutes(minutes) = new(Integer(minutes) * 60)
      def from_hours(hours) = new(Integer(hours) * 3600)
      def from_days(days) = new(Integer(days) * 86_400)

      # Accepts an Integer, a Duration, or anything that converts to seconds --
      # which includes ActiveSupport::Duration, without depending on it.
      def coerce(value)
        case value
        when Duration then value
        when Integer then new(value)
        when nil then nil
        else
          return new(value.to_i) if value.respond_to?(:to_i)

          raise ArgumentError, "cannot interpret #{value.inspect} as a Duration"
        end
      end
    end

    def to_i = @seconds
    alias to_seconds to_i

    def <=>(other) = other.is_a?(Duration) ? @seconds <=> other.seconds : nil
    def ==(other) = other.is_a?(Duration) && other.seconds == @seconds
    alias eql? ==
    def hash = [self.class, @seconds].hash

    def to_s = "#{@seconds}s"
    def inspect = "#<#{self.class} #{self}>"
  end
end
