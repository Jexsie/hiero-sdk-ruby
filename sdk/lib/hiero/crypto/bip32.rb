# frozen_string_literal: true

require "openssl"

module Hiero
  module Crypto
    # BIP-32 hierarchical derivation for secp256k1.
    #
    # Unlike SLIP-10 Ed25519, both hardened and unhardened derivation exist here
    # and mean different things, so indices are taken exactly as given. Use
    # {.harden} to set the hardening bit explicitly -- the standard Hiero ECDSA
    # path hardens its first three levels and not its last two.
    module Bip32
      MASTER_KEY = "Bitcoin seed"
      HARDENED_OFFSET = 0x8000_0000

      module_function

      # @param seed [String] the BIP-39 seed, 16 to 64 bytes
      # @return [Array(String, String)] the master key and chain code
      def from_seed(seed)
        seed = seed.b
        unless (16..64).cover?(seed.bytesize)
          raise ArgumentError, "seed must be 16-64 bytes, got #{seed.bytesize}"
        end

        key, chain_code = split(OpenSSL::HMAC.digest("SHA512", MASTER_KEY, seed))
        raise ArgumentError, "seed produced an invalid master key" unless valid_scalar?(key)

        [key, chain_code]
      end

      # @param index [Integer] hardened if >= 2**31
      # @return [Array(String, String)] the child key and chain code
      def derive(key, chain_code, index)
        key = key.b
        raise ArgumentError, "index out of range" unless (0...(HARDENED_OFFSET * 2)).cover?(index)

        data = if hardened?(index)
                 # A hardened child is derived from the private key, so it cannot be
                 # computed by anyone holding only the public key.
                 "\x00".b + key + [index].pack("N")
               else
                 Secp256k1.public_key_from_private(key) + [index].pack("N")
               end

        offset, child_chain_code = split(OpenSSL::HMAC.digest("SHA512", chain_code.b, data))

        # Vanishingly rare, but specified: an out-of-range offset or a zero child
        # means this index is skipped rather than producing a weak key.
        unless valid_scalar?(offset)
          raise KeyDerivationError, "index #{index} produced an invalid key; try the next index"
        end

        child = (to_int(offset) + to_int(key)) % Secp256k1::ORDER
        raise KeyDerivationError, "index #{index} produced a zero key; try the next index" if child.zero?

        [[child.to_s(16).rjust(64, "0")].pack("H*"), child_chain_code]
      end

      def harden(index) = index | HARDENED_OFFSET
      def hardened?(index) = (index & HARDENED_OFFSET) != 0

      def split(digest) = [digest[0, 32], digest[32, 32]]
      def to_int(bytes) = bytes.b.unpack1("H*").to_i(16)
      def valid_scalar?(bytes) = (value = to_int(bytes)).positive? && value < Secp256k1::ORDER
    end
  end
end
