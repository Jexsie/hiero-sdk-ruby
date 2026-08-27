# frozen_string_literal: true

require "openssl"

module Hiero
  module Crypto
    # ECDSA over secp256k1, on Ruby's stdlib OpenSSL.
    #
    # Hiero signs keccak256(message) and expects the 64-byte r||s form, with a
    # deterministic nonce (RFC 6979) and s normalised into the lower half of the
    # curve order. OpenSSL gives us the curve arithmetic but generates a random
    # nonce, so signatures differ run to run and cannot reproduce the signatures
    # the other SDKs produce.
    #
    # The nonce is therefore derived here rather than left to OpenSSL, and the
    # final scalar arithmetic is done directly. This is byte-for-byte identical to
    # libsecp256k1 on the cross-SDK test vectors -- see
    # docs/adr/0001-cryptography-backends.md -- and avoids a native dependency
    # that needs autotools to install.
    #
    # Determinism is not merely cosmetic. A repeated or predictable nonce leaks the
    # private key outright, so deriving it from the key and message rather than
    # from a random source removes an entire class of failure.
    module Secp256k1
      GROUP  = OpenSSL::PKey::EC::Group.new("secp256k1")
      ORDER  = GROUP.order.to_i
      HALF_ORDER = ORDER / 2
      FIELD_BYTES = 32

      PRIVATE_KEY_LENGTH   = 32
      SIGNATURE_LENGTH     = 64
      COMPRESSED_KEY_LENGTH = 33

      class << self
        # @param private_key [String] the raw 32-byte private key
        # @return [String] the 33-byte compressed public key
        def public_key_from_private(private_key)
          point(scalar(private_key)).to_octet_string(:compressed)
        end

        # @return [String] the 65-byte uncompressed public key, 0x04-prefixed
        def uncompressed_public_key(private_key)
          point(scalar(private_key)).to_octet_string(:uncompressed)
        end

        # Signs a digest that has ALREADY been hashed. Callers pass
        # Keccak.digest(message); this does not hash for them, because signing the
        # wrong digest is silent and unrecoverable and the choice belongs at the
        # call site.
        #
        # @param private_key [String] the raw 32-byte private key
        # @param digest [String] a 32-byte digest
        # @return [String] a 64-byte r||s signature, low-s normalised
        def sign_digest(private_key, digest)
          d = scalar(private_key)
          z = bits_to_int(digest) % ORDER

          each_nonce(d, digest) do |k|
            r = point(k).to_octet_string(:uncompressed)[1, FIELD_BYTES].unpack1("H*").to_i(16) % ORDER
            next if r.zero?

            k_inverse = OpenSSL::BN.new(k).mod_inverse(OpenSSL::BN.new(ORDER)).to_i
            s = (k_inverse * (z + r * d)) % ORDER
            next if s.zero?

            # Both s and ORDER - s are valid. Ethereum and Hiero accept only the
            # lower of the two, so that a signature has one canonical form.
            s = ORDER - s if s > HALF_ORDER

            return int_to_octets(r) + int_to_octets(s)
          end
        end

        # @param public_key [String] compressed or uncompressed public key
        # @param signature [String] a 64-byte r||s signature
        # @return [Boolean]
        def verify_digest(public_key, signature, digest)
          signature = signature.b
          return false unless signature.bytesize == SIGNATURE_LENGTH

          r = signature[0, FIELD_BYTES].unpack1("H*").to_i(16)
          s = signature[FIELD_BYTES, FIELD_BYTES].unpack1("H*").to_i(16)
          return false unless r.positive? && s.positive? && r < ORDER && s < ORDER

          der = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(r), OpenSSL::ASN1::Integer(s)]).to_der
          openssl_public_key(public_key).dsa_verify_asn1(digest.b, der)
        rescue OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error
          false
        end

        def generate_private_key
          loop do
            candidate = OpenSSL::Random.random_bytes(PRIVATE_KEY_LENGTH)
            value = bits_to_int(candidate)
            return candidate if value.positive? && value < ORDER
          end
        end

        private

        # RFC 6979 section 3.2: derive the nonce deterministically from the private
        # key and the digest, using HMAC-SHA256 as the PRF. Yields candidates until
        # the caller finds one that produces a usable signature.
        def each_nonce(private_scalar, digest)
          v = "\x01".b * 32
          k = "\x00".b * 32
          x = int_to_octets(private_scalar)
          h = int_to_octets(bits_to_int(digest) % ORDER)

          k = hmac(k, "#{v}\x00#{x}#{h}")
          v = hmac(k, v)
          k = hmac(k, "#{v}\x01#{x}#{h}")
          v = hmac(k, v)

          loop do
            v = hmac(k, v)
            candidate = bits_to_int(v)
            yield candidate if candidate.positive? && candidate < ORDER

            k = hmac(k, "#{v}\x00")
            v = hmac(k, v)
          end
        end

        def hmac(key, data) = OpenSSL::HMAC.digest("SHA256", key, data)

        def point(scalar_value) = GROUP.generator.mul(OpenSSL::BN.new(scalar_value))

        def openssl_public_key(public_key)
          point = OpenSSL::PKey::EC::Point.new(GROUP, OpenSSL::BN.new(public_key.b.unpack1("H*"), 16))
          asn1 = OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::Sequence([
              OpenSSL::ASN1::ObjectId("id-ecPublicKey"),
              OpenSSL::ASN1::ObjectId("secp256k1")
            ]),
            OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed))
          ])
          OpenSSL::PKey::EC.new(asn1.to_der)
        end

        # secp256k1's order is 256 bits and Hiero always signs 256-bit digests, so
        # RFC 6979's bits2int truncation never has anything to remove. Shorter
        # inputs are still handled correctly; longer ones are truncated as the spec
        # requires.
        def bits_to_int(bytes)
          bytes = bytes.b
          value = bytes.unpack1("H*").to_i(16)
          excess = (bytes.bytesize * 8) - 256
          excess.positive? ? value >> excess : value
        end

        def int_to_octets(value) = [value.to_s(16).rjust(FIELD_BYTES * 2, "0")].pack("H*")

        def scalar(private_key)
          private_key = private_key.b
          unless private_key.bytesize == PRIVATE_KEY_LENGTH
            raise ArgumentError, "expected a #{PRIVATE_KEY_LENGTH}-byte private key, got #{private_key.bytesize}"
          end

          value = bits_to_int(private_key)
          raise ArgumentError, "private key is out of range for secp256k1" unless value.positive? && value < ORDER

          value
        end
      end
    end
  end
end
