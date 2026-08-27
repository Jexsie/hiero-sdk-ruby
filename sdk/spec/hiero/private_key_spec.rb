# frozen_string_literal: true

RSpec.describe Hiero::PrivateKey do
  describe "parsing" do
    it "reads an Ed25519 key from DER" do
      key = described_class.from_string(Vectors::ED25519_PRIVATE_DER)

      expect(key).to be_ed25519
      expect(key.to_string_raw).to eq(Vectors::ED25519_PRIVATE_RAW)
    end

    it "reads an ECDSA key from DER" do
      key = described_class.from_string(Vectors::ECDSA_PRIVATE_DER)

      expect(key).to be_ecdsa
      expect(key.to_string_raw).to eq(Vectors::ECDSA_PRIVATE_RAW)
    end

    it "treats a bare 32-byte key as Ed25519, as the other SDKs do" do
      # Both algorithms use 32-byte private keys, so raw bytes carry nothing that
      # says which this is. Ed25519 is the documented default.
      expect(described_class.from_string(Vectors::ED25519_PRIVATE_RAW)).to be_ed25519
    end

    it "accepts an explicit algorithm for a raw ECDSA key" do
      key = described_class.from_string(Vectors::ECDSA_PRIVATE_RAW, algorithm: :ecdsa)

      expect(key).to be_ecdsa
      expect(key.public_key.to_string_raw).to eq(Vectors::ECDSA_PUBLIC_RAW)
    end

    it "refuses an algorithm hint alongside DER, which already says which it is" do
      expect { described_class.from_string(Vectors::ECDSA_PRIVATE_DER, algorithm: :ecdsa) }
        .to raise_error(ArgumentError, /only meaningful for raw keys/)
    end

    it "rejects a key of the wrong length" do
      expect { described_class.from_string("00" * 20) }.to raise_error(Hiero::BadKeyError)
    end

    it "rejects an ECDSA key outside the curve order" do
      expect { described_class.from_string("00" * 32, algorithm: :ecdsa) }
        .to raise_error(Hiero::BadKeyError, /out of range/)
    end
  end

  describe "public key derivation" do
    it "derives the matching Ed25519 public key" do
      expect(described_class.from_string(Vectors::ED25519_PRIVATE_DER).public_key.to_string_raw)
        .to eq(Vectors::ED25519_PUBLIC_RAW)
    end

    it "derives the matching ECDSA public key" do
      expect(described_class.from_string(Vectors::ECDSA_PRIVATE_DER).public_key.to_string_der)
        .to eq(Vectors::ECDSA_PUBLIC_DER)
    end
  end

  describe "signing" do
    %i[ed25519 ecdsa].each do |algorithm|
      context "with #{algorithm}" do
        let(:key) { described_class.generate(algorithm) }

        it "produces a 64-byte signature its public key verifies" do
          signature = key.sign("hiero")

          expect(signature.bytesize).to eq(64)
          expect(key.public_key.verify(signature, "hiero")).to be(true)
        end

        it "does not verify against different data" do
          expect(key.public_key.verify(key.sign("hiero"), "hiero!")).to be(false)
        end
      end
    end

    it "signs ECDSA over the keccak256 digest, matching the cross-SDK vector" do
      key = described_class.from_string(Vectors::ECDSA_PRIVATE, algorithm: :ecdsa)

      expect(key.sign(Vectors::ECDSA_MESSAGE).unpack1("H*")).to eq(Vectors::ECDSA_SIGNATURE)
    end
  end

  describe "not leaking key material" do
    let(:key) { described_class.from_string(Vectors::ED25519_PRIVATE_DER) }

    # In Ruby these are called implicitly by interpolation, puts, p, exception
    # formatting and every logging library, so a key that renders itself will
    # eventually be rendered somewhere it should not be.
    it "redacts #inspect" do
      expect(key.inspect).not_to include(Vectors::ED25519_PRIVATE_RAW)
      expect(key.inspect).to include("redacted")
    end

    it "redacts #to_s and therefore string interpolation" do
      expect("#{key}").not_to include(Vectors::ED25519_PRIVATE_RAW)
    end

    it "still exports when asked explicitly" do
      expect(key.to_string_der).to eq(Vectors::ED25519_PRIVATE_DER)
      expect(key.to_string_raw).to eq(Vectors::ED25519_PRIVATE_RAW)
    end

    it "refuses to Marshal" do
      expect { Marshal.dump(key) }.to raise_error(Hiero::BadKeyError, /Marshal/)
    end

    it "refuses to serialise to YAML" do
      expect { YAML.dump(key) }.to raise_error(Hiero::BadKeyError, /YAML/)
    end
  end

  describe "generation" do
    it "defaults to Ed25519" do
      expect(described_class.generate).to be_ed25519
    end

    it "generates distinct keys" do
      expect(described_class.generate_ed25519).not_to eq(described_class.generate_ed25519)
      expect(described_class.generate_ecdsa).not_to eq(described_class.generate_ecdsa)
    end

    it "rejects an unknown algorithm" do
      expect { described_class.generate(:rsa) }.to raise_error(ArgumentError, /unknown algorithm/)
    end
  end

  it "round-trips through DER" do
    %i[ed25519 ecdsa].each do |algorithm|
      key = described_class.generate(algorithm)

      expect(described_class.from_string(key.to_string_der)).to eq(key)
    end
  end

  it "is not a Key, because private keys never reach the network" do
    expect(described_class.generate).not_to be_a(Hiero::Key)
  end
end
