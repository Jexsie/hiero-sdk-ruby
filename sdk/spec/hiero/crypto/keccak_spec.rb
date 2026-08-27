# frozen_string_literal: true

RSpec.describe Hiero::Crypto::Keccak do
  it "computes the canonical empty-input digest" do
    expect(described_class.hexdigest("")).to eq(Vectors::KECCAK_EMPTY)
  end

  it "is Keccak, not SHA3-256" do
    # The two differ only in a padding byte, so a wrong choice here produces a
    # digest that looks entirely plausible and breaks every EVM address.
    expect(described_class.hexdigest("")).not_to eq(OpenSSL::Digest.hexdigest("SHA3-256", ""))
  end

  it "produces a 32-byte binary digest" do
    digest = described_class.digest("hello world")

    expect(digest.bytesize).to eq(32)
    expect(digest.encoding).to eq(Encoding::BINARY)
  end

  describe "block boundaries" do
    # The rate is 136 bytes. Inputs either side of it exercise the padding path
    # and the multi-block path, which is where a hand-written sponge goes wrong.
    [0, 1, 135, 136, 137, 272, 273].each do |length|
      it "handles a #{length}-byte input" do
        input = "a" * length

        expect(described_class.pure_digest(input).bytesize).to eq(32)
        expect(described_class.pure_digest(input)).to eq(described_class.digest(input))
      end
    end
  end

  it "agrees with the native implementation when one is installed" do
    skip "digest-keccak is not installed" unless described_class::NATIVE

    ["", "hello world", "a" * 200, "\x00\xFF".b * 71].each do |input|
      expect(described_class.pure_digest(input)).to eq(Digest::Keccak.digest(input.b, 256))
    end
  end
end
