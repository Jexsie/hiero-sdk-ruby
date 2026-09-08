# frozen_string_literal: true

module Hiero
  # One non-fungible token: a {TokenId} plus a serial number, written
  # `shard.realm.num/serial`.
  class NftId < Data.define(:token_id, :serial)
    include Comparable

    def initialize(token_id:, serial:)
      token_id = TokenId.coerce(token_id)
      serial = Integer(serial)
      raise ArgumentError, "an NFT serial number starts at 1" unless serial.positive?

      super
    end

    def self.from_string(text)
      token, serial = text.to_s.strip.split("/", 2)
      raise BadEntityIdError, "#{text.inspect} is not a valid NftId; expected shard.realm.num/serial" if serial.nil?

      new(token_id: TokenId.from_string(token), serial: Integer(serial))
    rescue ArgumentError, TypeError
      raise BadEntityIdError, "#{text.inspect} is not a valid NftId; expected shard.realm.num/serial"
    end

    def to_s = "#{token_id}/#{serial}"
    def inspect = "#<#{self.class} #{self}>"

    def <=>(other)
      return nil unless other.is_a?(NftId)

      [token_id, serial] <=> [other.token_id, other.serial]
    end
  end
end
