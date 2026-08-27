# frozen_string_literal: true

module Hiero
  module Crypto
    # Keccak-256, as used by Ethereum and by Hiero for ECDSA message hashing and
    # EVM address derivation.
    #
    # This is the ORIGINAL Keccak, not the standardised SHA3-256 that OpenSSL
    # provides. They differ only in the padding byte -- 0x01 here against 0x06 for
    # SHA3 -- which means SHA3-256 will happily return a plausible-looking digest
    # that is wrong for every Ethereum-compatible purpose. Reaching for
    # OpenSSL::Digest("SHA3-256") is the single easiest way to break EVM addresses.
    #
    # A pure-Ruby implementation is used by default so the SDK needs no native
    # cryptography dependency. If the optional digest-keccak gem is installed it is
    # picked up automatically and is around 400x faster; results are identical
    # either way.
    module Keccak
      MASK64 = 0xFFFF_FFFF_FFFF_FFFF

      # Rotation offsets and lane permutation for the rho and pi steps.
      ROTATION = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14,
                  27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44].freeze
      PERMUTE  = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
                  15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1].freeze

      ROUND_CONSTANTS = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
      ].freeze

      # Whether the optional native implementation was found. Exposed so that
      # applications can assert on it when hashing throughput actually matters.
      NATIVE = begin
        require "digest/keccak"
        true
      rescue LoadError
        false
      end

      class << self
        # @param message [String] bytes to hash
        # @return [String] the 32-byte digest, binary encoded
        def digest(message)
          return Digest::Keccak.digest(message.b, 256) if NATIVE

          pure_digest(message)
        end

        # @return [String] the 32-byte digest as lowercase hex
        def hexdigest(message) = digest(message).unpack1("H*")

        # The pure-Ruby path, always available and used by the specs to prove the
        # two implementations agree.
        def pure_digest(message)
          rate  = 136 # (1600 - 256 * 2) / 8
          state = Array.new(25, 0)

          padded(message.b, rate).bytes.each_slice(rate) do |block|
            block.each_slice(8).with_index do |lane, i|
              state[i] ^= lane.each_with_index.sum { |byte, k| byte << (8 * k) }
            end
            permute!(state)
          end

          state[0, 4].pack("Q<4")
        end

        private

        def padded(message, rate)
          out = +"#{message}\x01"
          out << "\x00" while (out.bytesize % rate) != 0
          out.setbyte(out.bytesize - 1, out.getbyte(out.bytesize - 1) | 0x80)
          out
        end

        def rotl(value, count) = ((value << count) | (value >> (64 - count))) & MASK64

        def permute!(state)
          ROUND_CONSTANTS.each do |round_constant|
            theta!(state)
            rho_pi!(state)
            chi!(state)
            state[0] ^= round_constant
          end
          state
        end

        def theta!(state)
          parity = (0..4).map { |x| state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
          (0..4).each do |x|
            d = parity[(x + 4) % 5] ^ rotl(parity[(x + 1) % 5], 1)
            (0..4).each { |y| state[x + 5 * y] ^= d }
          end
        end

        def rho_pi!(state)
          carried = state[1]
          24.times do |i|
            target = PERMUTE[i]
            held = state[target]
            state[target] = rotl(carried, ROTATION[i])
            carried = held
          end
        end

        def chi!(state)
          (0..4).each do |y|
            row = state[5 * y, 5]
            (0..4).each do |x|
              state[x + 5 * y] = row[x] ^ ((~row[(x + 1) % 5] & MASK64) & row[(x + 2) % 5])
            end
          end
        end
      end
    end
  end
end
