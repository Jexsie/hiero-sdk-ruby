# frozen_string_literal: true

module Hiero
  # A smart contract identifier: `shard.realm.num`, or a 20-byte EVM address for a
  # contract that has one.
  class ContractId < Data.define(:shard, :realm, :num, :checksum, :evm_address)
    include EntityId

    def initialize(num: nil, shard: 0, realm: 0, checksum: nil, evm_address: nil)
      raise ArgumentError, "a ContractId needs a num or an evm_address" if num.nil? && evm_address.nil?

      begin
        evm_address = Encoding.decode_evm_address(evm_address)
      rescue ArgumentError => e
        raise BadEntityIdError, e.message
      end

      super
    end

    def self.from_evm_address(address, shard: 0, realm: 0)
      bytes = Encoding.decode_evm_address(address)

      return from_solidity_address(bytes.unpack1("H*")) if AccountId.long_zero?(bytes)

      new(shard: shard, realm: realm, evm_address: bytes)
    end

    def evm_address? = !evm_address.nil?
    def numeric? = !num.nil?
    def evm_address_string = evm_address && Encoding.encode_hex(evm_address)

    def to_s
      return "#{shard}.#{realm}.#{evm_address_string}" if evm_address?

      super
    end
  end
end
