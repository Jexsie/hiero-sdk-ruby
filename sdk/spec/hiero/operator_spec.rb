# frozen_string_literal: true

RSpec.describe Hiero::Operator do
  let(:key) { Hiero::PrivateKey.generate_ed25519 }

  it "takes a local private key" do
    operator = described_class.new(account_id: "0.0.1001", private_key: key)

    expect(operator.account_id).to eq(Hiero::AccountId.new(num: 1001))
    expect(operator.public_key).to eq(key.public_key)
    expect(operator.public_key.verify(operator.sign("hiero"), "hiero")).to be(true)
  end

  it "takes a signer block instead, so the key can live in an HSM" do
    # The contract is only (String) -> String, which a KMS satisfies as readily as
    # a local key. This is what lets a server sign without holding key material.
    calls = 0
    operator = described_class.new(account_id: 1001, public_key: key.public_key) do |bytes|
      calls += 1
      key.sign(bytes)
    end

    expect(operator.public_key.verify(operator.sign("hiero"), "hiero")).to be(true)
    expect(calls).to eq(1)
  end

  it "refuses both a key and a signer" do
    expect { described_class.new(account_id: 1, private_key: key) { |b| b } }
      .to raise_error(ArgumentError, /not both/)
  end

  it "refuses neither" do
    expect { described_class.new(account_id: 1) }.to raise_error(ArgumentError, /needs a private_key/)
  end

  it "does not print key material" do
    operator = described_class.new(account_id: "0.0.1001", private_key: key)

    expect(operator.inspect).not_to include(key.to_string_raw)
    expect("#{operator}").not_to include(key.to_string_raw)
  end
end
