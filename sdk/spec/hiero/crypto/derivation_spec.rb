# frozen_string_literal: true

# These check the derivation primitives against the vectors published with their
# own specifications, rather than against another SDK. If BIP-32 and SLIP-10 are
# each correct in isolation, a Hiero path is just a walk over them -- and when a
# Hiero-path result later disagrees with another SDK, these say whether the fault
# is in the primitive or in the path.
RSpec.describe "key derivation" do
  SPEC_SEED = Vectors.bin("000102030405060708090a0b0c0d0e0f")

  describe Hiero::Crypto::Slip10 do
    # SLIP-0010 test vector 1, ed25519.
    it "derives the master key from a seed" do
      key, chain_code = described_class.from_seed(SPEC_SEED)

      expect(key.unpack1("H*")).to eq("2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7")
      expect(chain_code.unpack1("H*")).to eq("90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb")
    end

    it "walks the specification's chain" do
      expected = {
        [0] => "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3",
        [0, 1] => "b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2",
        [0, 1, 2] => "92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9",
        [0, 1, 2, 2] => "30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662",
        [0, 1, 2, 2, 1_000_000_000] => "8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793"
      }

      expected.each do |path, want|
        key, chain_code = described_class.from_seed(SPEC_SEED)
        path.each { |index| key, chain_code = described_class.derive(key, chain_code, index) }

        expect(key.unpack1("H*")).to eq(want), "path #{path.inspect}"
      end
    end

    it "refuses a pre-hardened index, since it hardens every level itself" do
      key, chain_code = described_class.from_seed(SPEC_SEED)

      expect { described_class.derive(key, chain_code, described_class::HARDENED_OFFSET) }
        .to raise_error(ArgumentError, /hardened automatically/)
    end
  end

  describe Hiero::Crypto::Bip32 do
    # BIP-32 test vector 1.
    it "derives the master key from a seed" do
      key, chain_code = described_class.from_seed(SPEC_SEED)

      expect(key.unpack1("H*")).to eq("e8f32e723decf4051aefac8e2c93c9c5b214313817cdb01a1494b917c8436b35")
      expect(chain_code.unpack1("H*")).to eq("873dff81c02f525623fd1fe5167eac3a55a049de3d314bb42ee227ffed37d508")
    end

    it "walks the specification's chain, mixing hardened and unhardened levels" do
      h = described_class.method(:harden)
      expected = {
        [h.(0)] => "edb2e14f9ee77d26dd93b4ecede8d16ed408ce149b6cd80b0715a2d911a0afea",
        [h.(0), 1] => "3c6cb8d0f6a264c91ea8b5030fadaa8e538b020f0a387421a12de9319dc93368",
        [h.(0), 1, h.(2)] => "cbce0d719ecf7431d88e6a89fa1483e02e35092af60c042b1df2ff59fa424dca",
        [h.(0), 1, h.(2), 2] => "0f479245fb19a38a1954c5c7c0ebab2f9bdfd96a17563ef28a6a4b1a2a764ef4",
        [h.(0), 1, h.(2), 2, 1_000_000_000] => "471b76e389e528d6de6d816857e012c5455051cad6660850e58372a6c3e6e7c8"
      }

      expected.each do |path, want|
        key, chain_code = described_class.from_seed(SPEC_SEED)
        path.each { |index| key, chain_code = described_class.derive(key, chain_code, index) }

        expect(key.unpack1("H*")).to eq(want), "path #{path.inspect}"
      end
    end

    it "distinguishes hardened from unhardened indices" do
      expect(described_class.harden(44)).to eq(44 + 2**31)
      expect(described_class).to be_hardened(described_class.harden(0))
      expect(described_class).not_to be_hardened(0)
    end

    it "rejects a seed outside the permitted length" do
      expect { described_class.from_seed("\x00".b * 8) }.to raise_error(ArgumentError, /16-64 bytes/)
    end
  end

  describe "hierarchical derivation on PrivateKey" do
    it "refuses to derive from a key with no chain code" do
      key = Hiero::PrivateKey.from_string(Vectors::ED25519_PRIVATE_DER)

      expect(key).not_to be_derivable
      expect { key.derive(0) }.to raise_error(Hiero::BadKeyError, /no chain code/)
    end

    it "carries a chain code through a seed and its children" do
      key = Hiero::PrivateKey.from_seed_ed25519(SPEC_SEED)

      expect(key).to be_derivable
      expect(key.derive(0)).to be_derivable
    end

    it "walks a whole path in one call" do
      root = Hiero::PrivateKey.from_seed_ed25519(SPEC_SEED)

      expect(root.derive_path(0, 1, 2)).to eq(root.derive(0).derive(1).derive(2))
    end
  end
end
