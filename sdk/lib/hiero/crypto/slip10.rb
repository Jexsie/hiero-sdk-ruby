# frozen_string_literal: true

require "openssl"

module Hiero
  module Crypto
    # SLIP-10 hierarchical derivation for Ed25519.
    #
    # Ed25519 has no public-key derivation, so every step is hardened; there is no
    # unhardened variant to choose. Indices are therefore given here unhardened and
    # the hardening bit is applied internally, which removes a whole category of
    # caller mistake.
    module Slip10
      MASTER_KEY = "ed25519 seed"
      HARDENED_OFFSET = 0x8000_0000

      module_function

      # @param seed [String] the BIP-39 seed
      # @return [Array(String, String)] the master key and chain code
      def from_seed(seed)
        split(OpenSSL::HMAC.digest("SHA512", MASTER_KEY, seed.b))
      end

      # @param key [String] the 32-byte parent key
      # @param chain_code [String] the 32-byte parent chain code
      # @param index [Integer] an unhardened index; hardening is applied here
      # @return [Array(String, String)] the child key and chain code
      def derive(key, chain_code, index)
        if index >= HARDENED_OFFSET
          raise ArgumentError, "SLIP-10 Ed25519 indices are hardened automatically; pass #{index - HARDENED_OFFSET}"
        end

        data = +"\x00".b
        data << key.b
        data << [index | HARDENED_OFFSET].pack("N")

        split(OpenSSL::HMAC.digest("SHA512", chain_code.b, data))
      end

      def split(digest) = [digest[0, 32], digest[32, 32]]
    end
  end
end
