# frozen_string_literal: true

require "openssl"

module Hiero
  module Crypto
    # Ed25519 signing, on Ruby's stdlib OpenSSL.
    #
    # Hiero keys are raw 32-byte seeds, while OpenSSL's PKey API is built around
    # DER. That mismatch is the usual reason SDKs reach for a native Ed25519 gem,
    # but it is not actually an obstacle: the DER encodings Hiero uses are a fixed
    # prefix followed by the key bytes, so converting either way is a concatenation.
    #
    # Everything here goes through DER deliberately. OpenSSL's raw key API
    # (new_raw_private_key, raw_public_key) is the more direct route but only
    # arrived in the openssl gem 3.2, and Ruby 3.2 -- the supported floor -- ships
    # 3.1.2. The underlying libssl supports Ed25519 in both cases; it is the Ruby
    # binding that differs, and PKey.read has been able to parse these structures
    # for far longer.
    module Ed25519
      SEED_LENGTH       = 32
      PUBLIC_KEY_LENGTH = 32
      SIGNATURE_LENGTH  = 64

      # PKCS#8 header for an Ed25519 private key: SEQUENCE, version 0,
      # AlgorithmIdentifier 1.3.101.112, OCTET STRING wrapping the 32-byte seed.
      DER_PRIVATE_PREFIX = ["302e020100300506032b657004220420"].pack("H*").freeze

      # SubjectPublicKeyInfo header for an Ed25519 public key.
      DER_PUBLIC_PREFIX = ["302a300506032b6570032100"].pack("H*").freeze

      class << self
        # @param seed [String] the raw 32-byte private key
        # @return [String] the raw 32-byte public key
        def public_key_from_seed(seed)
          spki = private_key(seed).public_to_der
          unless spki.bytesize == DER_PUBLIC_PREFIX.bytesize + PUBLIC_KEY_LENGTH &&
                 spki.start_with?(DER_PUBLIC_PREFIX)
            raise OpenSSL::PKey::PKeyError, "unexpected Ed25519 SubjectPublicKeyInfo encoding"
          end

          spki[DER_PUBLIC_PREFIX.bytesize, PUBLIC_KEY_LENGTH]
        end

        # @param seed [String] the raw 32-byte private key
        # @param message [String] bytes to sign
        # @return [String] a 64-byte signature
        def sign(seed, message)
          private_key(seed).sign(nil, message.b)
        end

        # @param public_key [String] the raw 32-byte public key
        # @return [Boolean] whether the signature is valid, false rather than
        #   raising when the signature is malformed
        def verify(public_key, signature, message)
          OpenSSL::PKey
            .read(public_key_to_der(public_key))
            .verify(nil, signature.b, message.b)
        rescue OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error
          false
        end

        # Ed25519 has no key derivation of its own; a seed is simply 32 random bytes.
        def generate_seed = OpenSSL::Random.random_bytes(SEED_LENGTH)

        def seed_to_der(seed)     = DER_PRIVATE_PREFIX + check_length(seed, SEED_LENGTH, "seed")
        def public_key_to_der(pk) = DER_PUBLIC_PREFIX + check_length(pk, PUBLIC_KEY_LENGTH, "public key")

        # Accepts either the raw 32-byte seed or the 48-byte DER encoding.
        def seed_from_der(der)
          bytes = der.b
          return bytes if bytes.bytesize == SEED_LENGTH
          unless bytes.bytesize == DER_PRIVATE_PREFIX.bytesize + SEED_LENGTH &&
                 bytes.start_with?(DER_PRIVATE_PREFIX)
            raise ArgumentError, "not a DER-encoded Ed25519 private key"
          end

          bytes[DER_PRIVATE_PREFIX.bytesize, SEED_LENGTH]
        end

        private

        def private_key(seed) = OpenSSL::PKey.read(seed_to_der(seed))

        def check_length(bytes, expected, what)
          bytes = bytes.b
          return bytes if bytes.bytesize == expected

          raise ArgumentError, "expected a #{expected}-byte #{what}, got #{bytes.bytesize} bytes"
        end
      end
    end
  end
end
