# frozen_string_literal: true

require "digest"

RSpec.describe Hiero::Mnemonic do
  describe "the shipped word list" do
    it "is byte-identical to the canonical BIP-39 English list" do
      # A single altered word would still produce valid-looking mnemonics that
      # decode to different entropy everywhere else, so this is checked by hash
      # rather than by spot-checking entries.
      expect(Digest::SHA256.file(Hiero::Crypto::Bip39::WORDLIST_PATH).hexdigest)
        .to eq("2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda")
      expect(Hiero::Crypto::Bip39::WORDLIST.length).to eq(2048)
    end
  end

  describe "BIP-39 test vectors" do
    it "turns all-zero entropy into the specification's words" do
      expect(described_class.from_entropy(Vectors.bin(Vectors::BIP39_ZERO_ENTROPY)).to_s)
        .to eq(Vectors::BIP39_ZERO_WORDS)
    end

    it "stretches those words into the specification's seed" do
      seed = described_class.from_string(Vectors::BIP39_ZERO_WORDS).to_seed("TREZOR")

      expect(seed.unpack1("H*")).to eq(Vectors::BIP39_ZERO_SEED_TREZOR)
      expect(seed.bytesize).to eq(64)
    end

    it "round-trips entropy through words" do
      entropy = Random.bytes(32)

      expect(described_class.from_entropy(entropy).to_entropy).to eq(entropy)
    end
  end

  describe "standard Hiero derivation" do
    it "derives the Ed25519 key at the Hiero path" do
      # m/44'/3030'/0'/0' -- the standard path adds the account index below this.
      key = Hiero::PrivateKey
            .from_seed_ed25519(described_class.from_string(Vectors::HIERO_ED25519_MNEMONIC).to_seed)
            .derive_path(44, 3030, 0, 0)

      expect(key.to_string_raw).to eq(Vectors::HIERO_ED25519_DERIVED)
    end

    it "derives an ECDSA chain matching the BIP-32 vectors" do
      h = Hiero::Crypto::Bip32.method(:harden)
      root = Hiero::PrivateKey
             .from_seed_ecdsa(described_class.from_string(Vectors::ETH_MNEMONIC).to_seed)
             .derive_path(h.(44), h.(60), h.(0), 0)

      expect(root.to_string_raw).to eq(Vectors::ETH_ROOT)
      expect(Vectors::ETH_CHILDREN.each_with_index.map { |_, i| root.derive(i).to_string_raw })
        .to eq(Vectors::ETH_CHILDREN)
    end

    it "hardens every level for Ed25519 and only the first three for ECDSA" do
      # Getting this backwards yields a perfectly valid key for a different
      # account, with nothing to indicate the mistake.
      mnemonic = described_class.from_string(Vectors::HIERO_ED25519_MNEMONIC)
      h = Hiero::Crypto::Bip32.method(:harden)

      expect(mnemonic.to_standard_ed25519_private_key.to_string_raw)
        .to eq(Hiero::PrivateKey.from_seed_ed25519(mnemonic.to_seed).derive_path(44, 3030, 0, 0, 0).to_string_raw)

      expect(mnemonic.to_standard_ecdsa_private_key.to_string_raw)
        .to eq(Hiero::PrivateKey.from_seed_ecdsa(mnemonic.to_seed)
                 .derive_path(h.(44), h.(3030), h.(0), 0, 0).to_string_raw)
    end

    it "gives a different key per account index" do
      mnemonic = described_class.from_string(Vectors::HIERO_ED25519_MNEMONIC)

      expect(mnemonic.to_standard_ed25519_private_key("", 0))
        .not_to eq(mnemonic.to_standard_ed25519_private_key("", 1))
    end

    it "gives a different key per passphrase" do
      # The passphrase is not a password on the mnemonic: a wrong one does not
      # fail, it silently unlocks a different wallet.
      mnemonic = described_class.from_string(Vectors::HIERO_ED25519_MNEMONIC)

      expect(mnemonic.to_standard_ed25519_private_key(""))
        .not_to eq(mnemonic.to_standard_ed25519_private_key("hunter2"))
    end

    it "produces usable signing keys" do
      key = described_class.generate.to_standard_ecdsa_private_key

      expect(key.public_key.verify(key.sign("hiero"), "hiero")).to be(true)
    end
  end

  describe "validation" do
    it "rejects a phrase of the wrong length" do
      expect { described_class.from_string("abandon abandon about") }
        .to raise_error(Hiero::BadMnemonicError) { |e| expect(e.reason).to eq(:length) }
    end

    it "reports which words are not in the list" do
      words = Vectors::BIP39_ZERO_WORDS.split
      words[3] = "hodl"
      words[7] = "lambo"

      expect { described_class.from_words(words) }
        .to raise_error(Hiero::BadMnemonicError) { |e|
          expect(e.reason).to eq(:unknown_word)
          expect(e.unknown_words).to eq(%w[hodl lambo])
        }
    end

    it "rejects a phrase whose checksum does not match" do
      # Every word is real and the length is right; one is simply wrong. Without
      # the checksum this would silently derive keys for the wrong wallet.
      words = Vectors::BIP39_ZERO_WORDS.split
      words[-1] = "zoo"

      expect { described_class.from_words(words) }
        .to raise_error(Hiero::BadMnemonicError) { |e| expect(e.reason).to eq(:checksum) }
    end

    it "normalises case and stray whitespace" do
      expect(described_class.from_string("  ABANDON  #{Vectors::BIP39_ZERO_WORDS.split.drop(1).join(' ')} ").to_s)
        .to eq(Vectors::BIP39_ZERO_WORDS)
    end

    it "accepts comma-separated phrases, as exported by some wallets" do
      expect(described_class.from_string(Vectors::BIP39_ZERO_WORDS.split.join(",")).to_s)
        .to eq(Vectors::BIP39_ZERO_WORDS)
    end
  end

  describe "generation" do
    it "defaults to 24 words" do
      expect(described_class.generate.length).to eq(24)
    end

    it "supports every valid length" do
      Hiero::Crypto::Bip39::VALID_LENGTHS.each do |length|
        expect(described_class.generate(length).length).to eq(length)
      end
    end

    it "rejects an unsupported length" do
      expect { described_class.generate(13) }.to raise_error(ArgumentError, /expected 12, 15, 18, 21, 24/)
    end

    it "generates distinct phrases" do
      expect(described_class.generate).not_to eq(described_class.generate)
    end
  end

  it "redacts #inspect, being a private key in another form" do
    mnemonic = described_class.from_string(Vectors::BIP39_ZERO_WORDS)

    expect(mnemonic.inspect).not_to include("abandon")
    expect(mnemonic.inspect).to include("redacted")
    expect(mnemonic.to_s).to eq(Vectors::BIP39_ZERO_WORDS) # explicit export still works
  end

  it "is Enumerable over its words" do
    expect(described_class.from_string(Vectors::BIP39_ZERO_WORDS).first).to eq("abandon")
  end
end
