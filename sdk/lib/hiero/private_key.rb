# frozen_string_literal: true

module Hiero
  # An Ed25519 or ECDSA secp256k1 private key.
  #
  # A private key is not a {Key}: it never goes to the network and has no place in
  # the protobuf Key structure. It exists to produce signatures and to hand out its
  # {#public_key}.
  #
  # ## On printing
  #
  # #to_s and #inspect are deliberately redacted, and this is a considered
  # divergence from the other Hiero SDKs, whose toString() returns the DER-encoded
  # private key.
  #
  # In Ruby those two methods are called constantly and implicitly -- by string
  # interpolation, by `puts`, by `p`, by exception formatting, and by every error
  # reporter and logging library. A key that renders itself on interpolation will
  # eventually be interpolated into a log line, and once it reaches an aggregator
  # it is compromised. Exporting a key is a deliberate act, so it needs a
  # deliberate method: {#to_string_der} or {#to_string_raw}.
  class PrivateKey
    ALGORITHMS = %i[ed25519 ecdsa].freeze
    LENGTH = 32

    ED25519_DER_PREFIX = Crypto::Ed25519::DER_PRIVATE_PREFIX
    ECDSA_DER_PREFIX   = ["3030020100300706052b8104000a04220420"].pack("H*").freeze

    attr_reader :algorithm

    def initialize(bytes, algorithm)
      raise ArgumentError, "unknown algorithm #{algorithm.inspect}" unless ALGORITHMS.include?(algorithm)

      @bytes = bytes.b.freeze
      @algorithm = algorithm
      validate!
      # Derived up front rather than memoised, because the instance is frozen and
      # because #inspect reports it -- a lazy derivation that failed would recurse
      # through inspect while building its own error message.
      @public_key = derive_public_key
      freeze
    end

    class << self
      def generate_ed25519 = new(Crypto::Ed25519.generate_seed, :ed25519)
      def generate_ecdsa   = new(Crypto::Secp256k1.generate_private_key, :ecdsa)

      # Defaults to Ed25519, the more common key type on Hiero.
      def generate(algorithm = :ed25519)
        case algorithm
        when :ed25519 then generate_ed25519
        when :ecdsa   then generate_ecdsa
        else raise ArgumentError, "unknown algorithm #{algorithm.inspect}"
        end
      end

      # Accepts a DER encoding of either algorithm, or a bare 32-byte key.
      #
      # A raw private key carries nothing that identifies its algorithm -- both are
      # 32 bytes -- so bare bytes are read as Ed25519, matching the other SDKs.
      # When the key is ECDSA and only the raw form is available, say so:
      # `PrivateKey.from_bytes(bytes, algorithm: :ecdsa)`.
      def from_bytes(bytes, algorithm: nil)
        bytes = bytes.b

        if bytes.bytesize == LENGTH
          return new(bytes, algorithm || :ed25519)
        end
        raise ArgumentError, "algorithm: is only meaningful for raw keys" if algorithm

        from_der(bytes)
      end

      def from_string(text, algorithm: nil) = from_bytes(Encoding.decode_hex(text), algorithm: algorithm)

      def from_bytes_ed25519(bytes) = new(Crypto::Ed25519.seed_from_der(bytes), :ed25519)

      def from_bytes_ecdsa(bytes)
        bytes = bytes.b
        return new(bytes, :ecdsa) if bytes.bytesize == LENGTH

        new(strip_prefix(bytes, ECDSA_DER_PREFIX) || raise(BadKeyError, "not a DER-encoded ECDSA private key"), :ecdsa)
      end

      def from_string_ed25519(text) = from_bytes_ed25519(Encoding.decode_hex(text))
      def from_string_ecdsa(text)   = from_bytes_ecdsa(Encoding.decode_hex(text))

      def from_der(bytes)
        bytes = bytes.b
        if (raw = strip_prefix(bytes, ED25519_DER_PREFIX))
          return new(raw, :ed25519)
        end
        if (raw = strip_prefix(bytes, ECDSA_DER_PREFIX))
          return new(raw, :ecdsa)
        end

        raise BadKeyError, "not a recognised private key encoding (#{bytes.bytesize} bytes)"
      end

      private

      def strip_prefix(bytes, prefix)
        return nil unless bytes.bytesize == prefix.bytesize + LENGTH && bytes.start_with?(prefix)

        bytes[prefix.bytesize, LENGTH]
      end
    end

    def ed25519? = @algorithm == :ed25519
    def ecdsa?   = @algorithm == :ecdsa

    attr_reader :public_key

    # ECDSA signs keccak256(message); Ed25519 signs the message itself. Both return
    # 64 bytes.
    #
    # @param message [String] the bytes to sign
    # @return [String] a 64-byte signature
    def sign(message)
      if ed25519?
        Crypto::Ed25519.sign(@bytes, message)
      else
        Crypto::Secp256k1.sign_digest(@bytes, Crypto::Keccak.digest(message))
      end
    end

    def to_bytes_raw = @bytes
    def to_bytes_der = der_prefix + @bytes
    def to_bytes     = to_bytes_der

    def to_string_raw = Encoding.encode_hex(@bytes)
    def to_string_der = Encoding.encode_hex(to_bytes_der)

    # Redacted on purpose -- see the note on this class.
    def to_s = inspect
    def inspect = "#<#{self.class} #{@algorithm} public=#{public_key.to_string_raw[0, 16]}... [private key redacted]>"

    # Serialising a private key through Marshal or YAML writes it to wherever that
    # output goes, usually a cache, a job queue or a session store. Export it
    # explicitly with #to_string_der if that is genuinely the intent.
    def _dump(_depth) = raise(BadKeyError, "refusing to Marshal a private key; use #to_string_der explicitly")
    def encode_with(_coder) = raise(BadKeyError, "refusing to serialise a private key to YAML; use #to_string_der explicitly")

    def ==(other)
      other.is_a?(PrivateKey) && other.algorithm == @algorithm && other.to_bytes_raw == @bytes
    end
    alias eql? ==

    def hash = [self.class, @algorithm, @bytes].hash

    private

    def der_prefix = ed25519? ? ED25519_DER_PREFIX : ECDSA_DER_PREFIX

    def derive_public_key
      raw = ed25519? ? Crypto::Ed25519.public_key_from_seed(@bytes) : Crypto::Secp256k1.public_key_from_private(@bytes)
      PublicKey.new(raw, @algorithm)
    end

    def validate!
      raise BadKeyError, "expected a #{LENGTH}-byte private key, got #{@bytes.bytesize}" unless @bytes.bytesize == LENGTH
      return if ed25519?

      value = @bytes.unpack1("H*").to_i(16)
      return if value.positive? && value < Crypto::Secp256k1::ORDER

      raise BadKeyError, "private key is out of range for secp256k1"
    end
  end
end
