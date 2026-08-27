# frozen_string_literal: true

RSpec.describe Hiero::Encoding do
  describe ".decode_hex" do
    it "decodes lowercase hex" do
      expect(described_class.decode_hex("deadbeef").unpack1("H*")).to eq("deadbeef")
    end

    it "tolerates a 0x prefix, uppercase, and surrounding whitespace" do
      # Keys get pasted from block explorers and JSON-RPC tooling, not only from
      # other SDKs.
      %w[0xDEADBEEF 0XdeadBEEF DEADBEEF].each do |input|
        expect(described_class.decode_hex("  #{input}  ").unpack1("H*")).to eq("deadbeef")
      end
    end

    it "rejects an odd number of digits" do
      expect { described_class.decode_hex("abc") }.to raise_error(ArgumentError, /odd number/)
    end

    it "rejects non-hex characters" do
      expect { described_class.decode_hex("zz") }.to raise_error(ArgumentError, /not a hex string/)
    end

    it "returns binary-encoded bytes" do
      expect(described_class.decode_hex("00ff").encoding).to eq(::Encoding::BINARY)
    end
  end

  describe ".encode_hex" do
    it "produces lowercase, unprefixed hex" do
      expect(described_class.encode_hex("\xDE\xAD\xBE\xEF".b)).to eq("deadbeef")
    end

    it "round-trips" do
      bytes = Random.bytes(64)

      expect(described_class.decode_hex(described_class.encode_hex(bytes))).to eq(bytes)
    end
  end
end
