# frozen_string_literal: true

RSpec.describe Hiero::Crypto::Secp256k1 do
  let(:private_key) { Vectors.bin(Vectors::ECDSA_PRIVATE) }

  def keccak(message) = Hiero::Crypto::Keccak.digest(message)

  describe "cross-SDK signature vectors" do
    # These are the reason this module derives its own RFC 6979 nonce instead of
    # letting OpenSSL pick one. With a random nonce the signature is still valid,
    # but it differs on every run and can never equal these bytes.
    it "reproduces the 'hello world' signature exactly" do
      signature = described_class.sign_digest(private_key, keccak(Vectors::ECDSA_MESSAGE))

      expect(signature.unpack1("H*")).to eq(Vectors::ECDSA_SIGNATURE)
    end

    it "reproduces the transaction-body signature exactly" do
      body = Vectors.bin(Vectors::ECDSA_BODY_BYTES)
      signature = described_class.sign_digest(private_key, keccak(body))

      expect(signature.unpack1("H*")).to eq(Vectors::ECDSA_BODY_SIGNATURE)
    end
  end

  it "is deterministic" do
    digest = keccak(Vectors::ECDSA_MESSAGE)

    expect(described_class.sign_digest(private_key, digest))
      .to eq(described_class.sign_digest(private_key, digest))
  end

  it "normalises s into the lower half of the curve order" do
    # Both s and ORDER - s verify. Hiero and the EVM accept only the lower one, so
    # a high-s signature is a rejected transaction rather than a wrong answer.
    20.times do |i|
      signature = described_class.sign_digest(private_key, keccak("message #{i}"))
      s = signature[32, 32].unpack1("H*").to_i(16)

      expect(s).to be <= described_class::HALF_ORDER
    end
  end

  it "produces a 64-byte r||s signature" do
    expect(described_class.sign_digest(private_key, keccak("hiero")).bytesize)
      .to eq(described_class::SIGNATURE_LENGTH)
  end

  describe "public keys" do
    it "derives a 33-byte compressed public key" do
      expect(described_class.public_key_from_private(private_key).bytesize)
        .to eq(described_class::COMPRESSED_KEY_LENGTH)
    end

    it "derives a 65-byte uncompressed public key" do
      uncompressed = described_class.uncompressed_public_key(private_key)

      expect(uncompressed.bytesize).to eq(65)
      expect(uncompressed.getbyte(0)).to eq(0x04)
    end
  end

  describe "verification" do
    let(:digest) { keccak(Vectors::ECDSA_MESSAGE) }
    let(:signature) { described_class.sign_digest(private_key, digest) }

    it "accepts a valid signature against the compressed key" do
      public_key = described_class.public_key_from_private(private_key)

      expect(described_class.verify_digest(public_key, signature, digest)).to be(true)
    end

    it "accepts a valid signature against the uncompressed key" do
      public_key = described_class.uncompressed_public_key(private_key)

      expect(described_class.verify_digest(public_key, signature, digest)).to be(true)
    end

    it "rejects a signature over a different digest" do
      expect(described_class.verify_digest(
               described_class.public_key_from_private(private_key), signature, keccak("other")
             )).to be(false)
    end

    it "returns false rather than raising on malformed input" do
      public_key = described_class.public_key_from_private(private_key)

      expect(described_class.verify_digest(public_key, "short", digest)).to be(false)
      expect(described_class.verify_digest(public_key, "\x00".b * 64, digest)).to be(false)
    end
  end

  describe "key validation" do
    it "rejects a key of the wrong length" do
      expect { described_class.public_key_from_private("short") }
        .to raise_error(ArgumentError, /32-byte private key/)
    end

    it "rejects zero" do
      expect { described_class.public_key_from_private("\x00".b * 32) }
        .to raise_error(ArgumentError, /out of range/)
    end

    it "rejects a scalar at or above the curve order" do
      expect { described_class.public_key_from_private(Vectors.bin(described_class::ORDER.to_s(16))) }
        .to raise_error(ArgumentError, /out of range/)
    end
  end

  it "generates usable private keys" do
    generated = described_class.generate_private_key
    digest = keccak("hiero")

    expect(described_class.verify_digest(
             described_class.public_key_from_private(generated),
             described_class.sign_digest(generated, digest),
             digest
           )).to be(true)
  end
end
