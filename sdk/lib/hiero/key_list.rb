# frozen_string_literal: true

module Hiero
  # A list of keys, optionally with a threshold.
  #
  # With no threshold every key in the list must sign. With one, any `threshold`
  # of them will do. Hiero models these as two protobuf shapes -- KeyList and
  # ThresholdKey -- but they are the same idea, so this is one class and the
  # presence of a threshold picks the encoding.
  #
  # Lists nest: a member may itself be a KeyList.
  class KeyList < Key
    include Enumerable

    attr_reader :keys
    attr_accessor :threshold

    # @param keys [Array<Key>]
    # @param threshold [Integer, nil] how many must sign; nil means all of them
    def initialize(keys = [], threshold: nil)
      @keys = []
      Array(keys).each { |key| add(key) }
      self.threshold = threshold
      super()
    end

    def self.of(*keys) = new(keys)

    # @param threshold [Integer] how many of the given keys must sign
    def self.with_threshold(threshold, *keys) = new(keys.flatten, threshold: threshold)

    def threshold=(value)
      unless value.nil?
        value = Integer(value)
        raise ArgumentError, "threshold must be positive" unless value.positive?
      end
      @threshold = value
    end

    def add(key)
      raise ArgumentError, "expected a Hiero::Key, got #{key.class}" unless key.is_a?(Key)

      @keys << key
      self
    end
    alias << add

    def each(&) = @keys.each(&)
    def size = @keys.size
    alias length size
    def empty? = @keys.empty?

    # @return [Boolean] whether a threshold is set, which decides whether this
    #   encodes as a ThresholdKey rather than a plain KeyList
    def threshold? = !@threshold.nil?

    def ==(other)
      other.is_a?(KeyList) && other.keys == @keys && other.threshold == @threshold
    end
    alias eql? ==

    def hash = [self.class, @keys, @threshold].hash

    def to_s = inspect

    def inspect
      "#<#{self.class}#{@threshold ? " threshold=#{@threshold}/#{size}" : " #{size} keys"} #{@keys.inspect}>"
    end
  end
end
