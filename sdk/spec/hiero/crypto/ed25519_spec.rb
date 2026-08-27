# frozen_string_literal: true

RSpec.describe Hiero::Crypto::Ed25519 do
  let(:seed) { Vectors.bin(Vectors::ED25519_SEED) }
  let(:public_key) { Vectors.bin(Vectors::ED25519_PUBLIC) }

  it "derives the cross-SDK public key from a raw seed" do
    expect(described_class.public_key_from_seed(seed).unpack1("H*")).to eq(Vectors::ED25519_PUBLIC)
  end

  it "signs and verifies" do
    signature = described_class.sign(seed, "hiero")

    expect(signature.bytesize).to eq(described_class::SIGNATURE_LENGTH)
    expect(described_class.verify(public_key, signature, "hiero")).to be(true)
  end

  it "rejects a signature over different data" do
    signature = described_class.sign(seed, "hiero")

    expect(described_class.verify(public_key, signature, "hiero!")).to be(false)
  end

  it "returns false rather than raising on a malformed signature" do
    expect(described_class.verify(public_key, "too short", "hiero")).to be(false)
  end

  describe "DER encoding" do
    it "round-trips the private key through the Hiero DER form" do
      der = described_class.seed_to_der(seed)

      expect(der.unpack1("H*")).to eq(Vectors::ED25519_SEED_DER)
      expect(described_class.seed_from_der(der)).to eq(seed)
    end

    it "accepts a raw seed where DER is expected" do
      expect(described_class.seed_from_der(seed)).to eq(seed)
    end

    it "rejects bytes that are neither" do
      expect { described_class.seed_from_der("x" * 48) }.to raise_error(ArgumentError, /not a DER/)
    end
  end

  it "generates usable seeds" do
    generated = described_class.generate_seed

    expect(generated.bytesize).to eq(32)
    expect(
      described_class.verify(
        described_class.public_key_from_seed(generated),
        described_class.sign(generated, "hiero"),
        "hiero"
      )
    ).to be(true)
  end

  it "rejects a seed of the wrong length" do
    expect { described_class.public_key_from_seed("short") }.to raise_error(ArgumentError, /32-byte seed/)
  end
end
