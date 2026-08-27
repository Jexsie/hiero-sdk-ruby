# frozen_string_literal: true

module Hiero
  # An Ed25519 or ECDSA secp256k1 public key.
  #
  # Both algorithms are represented by this one class, matching how the other
  # Hiero SDKs present them, with #algorithm distinguishing the two. Raw encodings
  # are self-describing by length -- Ed25519 keys are 32 bytes and compressed
  # secp256k1 keys are 33 -- so a raw public key never needs a type hint, unlike a
  # raw private key.
  class PublicKey < Key
    ED25519_LENGTH = 32
    ECDSA_LENGTH   = 33

    # DER prefixes, as SubjectPublicKeyInfo.
    ED25519_DER_PREFIX = ["302a300506032b6570032100"].pack("H*").freeze
    ECDSA_DER_PREFIX   = ["302d300706052b8104000a032200"].pack("H*").freeze

    # Hiero emits the compact ECDSA form above, but the fully qualified X.509
    # encoding, which spells out id-ecPublicKey, is also valid and turns up in
    # keys produced elsewhere. Accept it on input; never emit it.
    ECDSA_DER_PREFIX_X509 = ["3036301006072a8648ce3d020106052b8104000a032200"].pack("H*").freeze

    attr_reader :algorithm

    # @param bytes [String] the raw key
    # @param algorithm [Symbol] :ed25519 or :ecdsa
    def initialize(bytes, algorithm)
      raise ArgumentError, "unknown algorithm #{algorithm.inspect}" unless %i[ed25519 ecdsa].include?(algorithm)

      @bytes = bytes.b.freeze
      @algorithm = algorithm
      validate!
      freeze
    end

    class << self
      # Accepts a raw key, or either DER encoding. Raw keys are distinguished by
      # length, so no hint is needed.
      def from_bytes(bytes)
        bytes = bytes.b

        return new(bytes, :ed25519) if bytes.bytesize == ED25519_LENGTH
        return new(bytes, :ecdsa)   if bytes.bytesize == ECDSA_LENGTH

        from_der(bytes)
      end

      def from_string(text) = from_bytes(Encoding.decode_hex(text))

      def from_bytes_ed25519(bytes) = new(strip_prefix(bytes, ED25519_DER_PREFIX, ED25519_LENGTH), :ed25519)

      def from_bytes_ecdsa(bytes)
        raw = strip_prefix(bytes, ECDSA_DER_PREFIX, ECDSA_LENGTH) ||
              strip_prefix(bytes, ECDSA_DER_PREFIX_X509, ECDSA_LENGTH)
        new(raw, :ecdsa)
      end

      def from_der(bytes)
        bytes = bytes.b
        if (raw = strip_prefix(bytes, ED25519_DER_PREFIX, ED25519_LENGTH))
          return new(raw, :ed25519)
        end

        raw = strip_prefix(bytes, ECDSA_DER_PREFIX, ECDSA_LENGTH) ||
              strip_prefix(bytes, ECDSA_DER_PREFIX_X509, ECDSA_LENGTH)
        return new(raw, :ecdsa) if raw

        raise BadKeyError, "not a recognised public key encoding (#{bytes.bytesize} bytes)"
      end

      private

      def strip_prefix(bytes, prefix, length)
        bytes = bytes.b
        return bytes if bytes.bytesize == length && prefix.nil?
        return nil unless bytes.bytesize == prefix.bytesize + length && bytes.start_with?(prefix)

        bytes[prefix.bytesize, length]
      end
    end

    def ed25519? = @algorithm == :ed25519
    def ecdsa?   = @algorithm == :ecdsa

    # @param signature [String] a 64-byte signature
    # @param message [String] the bytes that were signed
    # @return [Boolean] false rather than raising when the signature is malformed
    def verify(signature, message)
      if ed25519?
        Crypto::Ed25519.verify(@bytes, signature, message)
      else
        Crypto::Secp256k1.verify_digest(@bytes, signature, Crypto::Keccak.digest(message))
      end
    end

    # The 20-byte EVM address for this key: the last 20 bytes of the keccak256
    # hash of the uncompressed point, minus its 0x04 prefix.
    #
    # Ed25519 keys have no EVM address -- the derivation is specific to secp256k1
    # and there is no meaningful answer to return.
    def to_evm_address
      raise BadKeyError, "only ECDSA secp256k1 keys have an EVM address" unless ecdsa?

      Crypto::Keccak.digest(Crypto::Secp256k1.decompress(@bytes)[1..])[-20, 20]
    end

    def to_evm_address_string = Encoding.encode_hex(to_evm_address)

    def to_bytes_raw = @bytes
    def to_bytes_der = der_prefix + @bytes
    def to_bytes     = to_bytes_der

    def to_string_raw = Encoding.encode_hex(@bytes)
    def to_string_der = Encoding.encode_hex(to_bytes_der)

    # DER hex, which is the form the other Hiero SDKs print and accept.
    def to_s = to_string_der

    def inspect = "#<#{self.class} #{@algorithm} #{to_string_raw}>"

    def ==(other)
      other.is_a?(PublicKey) && other.algorithm == @algorithm && other.to_bytes_raw == @bytes
    end
    alias eql? ==

    def hash = [self.class, @algorithm, @bytes].hash

    private

    def der_prefix = ed25519? ? ED25519_DER_PREFIX : ECDSA_DER_PREFIX

    def validate!
      expected = ed25519? ? ED25519_LENGTH : ECDSA_LENGTH
      unless @bytes.bytesize == expected
        raise BadKeyError, "expected a #{expected}-byte #{@algorithm} public key, got #{@bytes.bytesize}"
      end

      return unless ecdsa? && !Crypto::Secp256k1.valid_public_key?(@bytes)

      raise BadKeyError, "not a valid point on secp256k1"
    end
  end
end
