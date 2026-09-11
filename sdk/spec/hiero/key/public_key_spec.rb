# frozen_string_literal: true

RSpec.describe Hiero::PublicKey do
  describe "parsing" do
    it "reads an Ed25519 key from raw bytes, identified by its 32-byte length" do
      key = described_class.from_string(Vectors::ED25519_PUBLIC_RAW)

      expect(key).to be_ed25519
      expect(key.to_string_raw).to eq(Vectors::ED25519_PUBLIC_RAW)
    end

    it "reads an ECDSA key from raw bytes, identified by its 33-byte length" do
      key = described_class.from_string(Vectors::ECDSA_PUBLIC_RAW)

      expect(key).to be_ecdsa
      expect(key.to_string_raw).to eq(Vectors::ECDSA_PUBLIC_RAW)
    end

    it "reads either algorithm from DER" do
      expect(described_class.from_string(Vectors::ED25519_PUBLIC_DER)).to be_ed25519
      expect(described_class.from_string(Vectors::ECDSA_PUBLIC_DER)).to be_ecdsa
    end

    it "accepts the fully qualified X.509 ECDSA encoding but does not emit it" do
      key = described_class.from_string(Vectors::ECDSA_PUBLIC_DER_X509)

      expect(key.to_string_raw).to eq(Vectors::ECDSA_PUBLIC_RAW)
      expect(key.to_string_der).to eq(Vectors::ECDSA_PUBLIC_DER)
    end

    it "tolerates a 0x prefix and uppercase hex" do
      expect(described_class.from_string("0x#{Vectors::ED25519_PUBLIC_RAW.upcase}").to_string_raw)
        .to eq(Vectors::ED25519_PUBLIC_RAW)
    end

    it "rejects an unrecognised encoding" do
      expect { described_class.from_string("00" * 40) }.to raise_error(Hiero::BadKeyError, /not a recognised/)
    end

    it "rejects bytes that are not a point on secp256k1" do
      expect { described_class.from_string("03#{'11' * 32}") }
        .to raise_error(Hiero::BadKeyError, /not a valid point/)
    end
  end

  describe "encoding" do
    it "round-trips Ed25519 through raw and DER" do
      key = described_class.from_string(Vectors::ED25519_PUBLIC_DER)

      expect(key.to_string_der).to eq(Vectors::ED25519_PUBLIC_DER)
      expect(described_class.from_string(key.to_string_raw)).to eq(key)
    end

    it "round-trips ECDSA through raw and DER" do
      key = described_class.from_string(Vectors::ECDSA_PUBLIC_DER)

      expect(key.to_string_der).to eq(Vectors::ECDSA_PUBLIC_DER)
      expect(described_class.from_string(key.to_string_raw)).to eq(key)
    end

    it "prints as DER hex, the form the other SDKs accept" do
      expect(described_class.from_string(Vectors::ED25519_PUBLIC_RAW).to_s)
        .to eq(Vectors::ED25519_PUBLIC_DER)
    end
  end

  describe "#to_evm_address" do
    it "derives the address for a secp256k1 key" do
      expect(described_class.from_string(Vectors::EVM_PUBLIC_KEY).to_evm_address_string)
        .to eq(Vectors::EVM_ADDRESS)
    end

    it "returns 20 bytes" do
      expect(described_class.from_string(Vectors::ECDSA_PUBLIC_RAW).to_evm_address.bytesize).to eq(20)
    end

    it "refuses for Ed25519, which has no EVM address" do
      expect { described_class.from_string(Vectors::ED25519_PUBLIC_RAW).to_evm_address }
        .to raise_error(Hiero::BadKeyError, /only ECDSA/)
    end
  end

  describe "equality" do
    it "compares by algorithm and bytes" do
      a = described_class.from_string(Vectors::ED25519_PUBLIC_RAW)
      b = described_class.from_string(Vectors::ED25519_PUBLIC_DER)

      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
      expect([a, b].uniq.length).to eq(1)
    end

    it "is not equal to a different key" do
      expect(described_class.from_string(Vectors::ED25519_PUBLIC_RAW))
        .not_to eq(described_class.from_string(Vectors::ECDSA_PUBLIC_RAW))
    end
  end

  it "is a Key, so it can appear in a KeyList" do
    expect(described_class.from_string(Vectors::ED25519_PUBLIC_RAW)).to be_a(Hiero::Key)
  end
end
