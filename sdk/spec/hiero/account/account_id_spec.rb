# frozen_string_literal: true

RSpec.describe Hiero::AccountId do
  describe "aliased accounts" do
    let(:public_key) { Hiero::PrivateKey.generate_ecdsa.public_key }

    it "can be addressed by the key that will own it, before it has a number" do
      id = described_class.from_alias_key(public_key)

      expect(id).to be_alias_key
      expect(id).not_to be_numeric
      expect(id.to_s).to eq("0.0.#{public_key.to_string_raw}")
    end

    it "has no checksum, there being no entity number to checksum" do
      expect { described_class.from_alias_key(public_key).checksum_for(:mainnet) }
        .to raise_error(Hiero::BadEntityIdError, /aliased/)
    end

    it "has no solidity address" do
      expect { described_class.from_alias_key(public_key).to_solidity_address }
        .to raise_error(Hiero::BadEntityIdError, /aliased/)
    end
  end

  describe "EVM addresses" do
    it "keeps a genuine EVM address as an alias" do
      id = described_class.from_evm_address("0x#{Vectors::EVM_ADDRESS}")

      expect(id).to be_evm_address
      expect(id).not_to be_numeric
      expect(id.evm_address_string).to eq(Vectors::EVM_ADDRESS)
    end

    it "decodes a long-zero address back to shard.realm.num" do
      # Twelve leading zero bytes mean the address only encodes an entity number,
      # so it is the same account written a different way -- not an alias.
      long_zero = "0x#{'00' * 12}#{'3'.rjust(16, '0')}"
      id = described_class.from_evm_address(long_zero)

      expect(id).to be_numeric
      expect(id).not_to be_evm_address
      expect(id).to eq(described_class.from_string("0.0.3"))
    end

    it "accepts raw bytes as readily as hex" do
      # Both arrive as Ruby Strings; length is what tells them apart.
      raw = Vectors.bin(Vectors::EVM_ADDRESS)

      expect(described_class.new(evm_address: raw).evm_address_string).to eq(Vectors::EVM_ADDRESS)
      expect(described_class.new(evm_address: Vectors::EVM_ADDRESS).evm_address_string)
        .to eq(Vectors::EVM_ADDRESS)
    end

    it "rejects a wrongly sized address" do
      expect { described_class.new(evm_address: "00" * 19) }
        .to raise_error(Hiero::BadEntityIdError, /20 bytes/)
    end
  end

  it "needs at least one way to identify the account" do
    expect { described_class.new }.to raise_error(ArgumentError, /num, an alias_key or an evm_address/)
  end

  it "distinguishes accounts that differ only by alias" do
    a = described_class.from_evm_address("0x#{Vectors::EVM_ADDRESS}")
    b = described_class.from_string("0.0.123")

    expect(a).not_to eq(b)
  end

  it "defaults shard and realm to zero" do
    id = described_class.new(num: 42)

    expect(id.to_s).to eq("0.0.42")
  end
end
