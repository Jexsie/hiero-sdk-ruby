# frozen_string_literal: true

module Hiero
  # An account identifier.
  #
  # Usually `shard.realm.num`, but an account can also be addressed before it has
  # a number, by the public key that will own it (an alias) or by a 20-byte EVM
  # address. Exactly one of those three forms identifies a given AccountId.
  class AccountId < Data.define(:shard, :realm, :num, :checksum, :alias_key, :evm_address)
    include EntityId

    def initialize(num: nil, shard: 0, realm: 0, checksum: nil, alias_key: nil, evm_address: nil)
      if [num, alias_key, evm_address].compact.empty?
        raise ArgumentError, "an AccountId needs a num, an alias_key or an evm_address"
      end

      begin
        evm_address = Encoding.decode_evm_address(evm_address)
      rescue ArgumentError => e
        raise BadEntityIdError, e.message
      end

      super(num: num, shard: shard, realm: realm, checksum: checksum,
            alias_key: alias_key, evm_address: evm_address)
    end

    class << self
      # An account addressed by the public key that owns it, before the network has
      # assigned it a number.
      def from_alias_key(public_key, shard: 0, realm: 0)
        new(shard: shard, realm: realm, alias_key: PublicKey.from_bytes(public_key.to_bytes_raw))
      end

      # An account addressed by a 20-byte EVM address.
      #
      # A long-zero address (twelve leading zero bytes) is really a
      # `shard.realm.num` in disguise, so it is decoded rather than stored -- that
      # is what makes it comparable to the same account written the usual way.
      def from_evm_address(address, shard: 0, realm: 0)
        bytes = Encoding.decode_evm_address(address)

        return from_solidity_address(bytes.unpack1("H*")) if long_zero?(bytes)

        new(shard: shard, realm: realm, evm_address: bytes)
      end

      # Whether the first twelve bytes are zero, which marks an EVM address that
      # merely encodes an entity number.
      def long_zero?(bytes) = bytes[0, 12] == ("\x00".b * 12)
    end

    def alias_key?   = !alias_key.nil?
    def evm_address? = !evm_address.nil?

    # @return [Boolean] whether this is a plain shard.realm.num identifier
    def numeric? = !num.nil?

    def evm_address_string = evm_address && Encoding.encode_hex(evm_address)

    def to_s
      return "#{shard}.#{realm}.#{alias_key.to_string_raw}" if alias_key?
      return "#{shard}.#{realm}.#{evm_address_string}" if evm_address?

      super
    end

    # An aliased account has no entity number, so there is nothing to checksum.
    def checksum_for(ledger)
      raise BadEntityIdError, "an aliased AccountId has no checksum" unless numeric?

      super
    end

    def to_solidity_address
      raise BadEntityIdError, "an aliased AccountId has no solidity address" unless numeric?

      super
    end

    def ==(other)
      other.instance_of?(self.class) && other.shard == shard && other.realm == realm &&
        other.num == num && other.alias_key == alias_key && other.evm_address == evm_address
    end
    alias eql? ==

    def hash = [self.class, shard, realm, num, alias_key, evm_address].hash
  end
end
