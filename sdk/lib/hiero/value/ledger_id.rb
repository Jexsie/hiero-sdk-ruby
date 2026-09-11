# frozen_string_literal: true

module Hiero
  # Identifies which Hiero network an entity belongs to.
  #
  # Its main job is scoping checksums. The same `0.0.123` checksums differently on
  # every network, so an ID copied from a mainnet explorer into a testnet
  # application fails loudly instead of silently addressing a different entity.
  class LedgerId
    NAMES = { 0 => "mainnet", 1 => "testnet", 2 => "previewnet" }.freeze

    attr_reader :bytes

    def initialize(bytes)
      @bytes = bytes.b.freeze
      freeze
    end

    MAINNET    = new("\x00".b)
    TESTNET    = new("\x01".b)
    PREVIEWNET = new("\x02".b)

    class << self
      # Accepts a name, a LedgerId, or the hex form of an unrecognised ledger.
      def from_string(text)
        case text.to_s.downcase
        when "mainnet" then MAINNET
        when "testnet" then TESTNET
        when "previewnet" then PREVIEWNET
        else new(Encoding.decode_hex(text))
        end
      end

      def from_bytes(bytes) = new(bytes)

      # Accepts anything that can name a ledger, so callers can pass :testnet.
      def coerce(value)
        case value
        when LedgerId then value
        when Symbol, String then from_string(value)
        when nil then nil
        else
          raise ArgumentError, "cannot interpret #{value.inspect} as a LedgerId"
        end
      end
    end

    def mainnet?    = self == MAINNET
    def testnet?    = self == TESTNET
    def previewnet? = self == PREVIEWNET

    # @return [Boolean] whether this is one of the three public networks. A local
    #   or custom network has its own ledger id and no well-known name.
    def known? = !name.nil?

    def name
      NAMES[@bytes.getbyte(0)] if @bytes.bytesize == 1
    end

    def to_bytes = @bytes
    def to_s = name || Encoding.encode_hex(@bytes)

    def ==(other) = other.is_a?(LedgerId) && other.bytes == @bytes
    alias eql? ==

    def hash = [self.class, @bytes].hash

    def inspect = "#<#{self.class} #{self}>"
  end
end
