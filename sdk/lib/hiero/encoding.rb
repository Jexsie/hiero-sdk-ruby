# frozen_string_literal: true

module Hiero
  # Byte-string encodings shared across the SDK.
  #
  # The JavaScript SDK needs three implementations of this, swapped by the bundler
  # per platform. Ruby needs one.
  module Encoding
    module_function

    # @param bytes [String]
    # @return [String] lowercase hex, unprefixed
    def encode_hex(bytes) = bytes.b.unpack1("H*")

    # Accepts an optional 0x prefix and either case, because keys get pasted from
    # block explorers and JSON-RPC tooling as often as from other SDKs.
    #
    # @param text [String]
    # @return [String] binary-encoded bytes
    def decode_hex(text)
      cleaned = text.to_s.strip.delete_prefix("0x").delete_prefix("0X")
      raise ArgumentError, "hex string has an odd number of digits" if cleaned.length.odd?
      raise ArgumentError, "not a hex string: #{text.inspect}" unless cleaned.match?(/\A[0-9a-fA-F]*\z/)

      [cleaned].pack("H*")
    end

    # A 20-byte EVM address, given either as raw bytes or as hex.
    #
    # Both arrive as Ruby Strings, so the two are told apart by length: an address
    # is 20 bytes raw and 40 characters as hex, which never collide. Guessing by
    # content instead would misread raw bytes that happen to be all ASCII hex
    # digits.
    #
    # @return [String, nil] 20 binary bytes
    def decode_evm_address(value)
      return nil if value.nil?

      bytes = value.b
      return bytes if bytes.bytesize == EVM_ADDRESS_LENGTH

      decoded = decode_hex(value)
      unless decoded.bytesize == EVM_ADDRESS_LENGTH
        raise ArgumentError, "an EVM address is #{EVM_ADDRESS_LENGTH} bytes, got #{decoded.bytesize}"
      end

      decoded
    end

    EVM_ADDRESS_LENGTH = 20
  end
end
