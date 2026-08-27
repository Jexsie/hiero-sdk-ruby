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
  end
end
