# frozen_string_literal: true

# Proves the operator handed over by the environment is usable. In CI that
# environment comes from hiero-solo-action's outputs, so this is what catches a
# broken handoff -- without it, a mistyped output name would leave every
# operator-dependent spec quietly skipped and the suite green.
#
# It does not yet prove the key can sign anything the network accepts; nothing
# here signs. That arrives with the transaction layer.
RSpec.describe "the configured operator", :integration, :operator do
  let(:client) { Solo.client }

  after { client.close }

  it "is attached to the client" do
    expect(client.operator).to be_a(Hiero::Operator)
    expect(client.operator_account_id).to be_a(Hiero::AccountId)
  end

  it "parsed a real key out of the environment" do
    # hiero-solo-action emits the private key DER-encoded, which is what
    # PrivateKey.from_string expects.
    expect(client.operator.public_key).to be_a(Hiero::PublicKey)
    expect(client.operator.sign("hiero").bytesize).to eq(64)
  end

  it "names an account that exists and is funded" do
    # A payer with no balance fails every paid request later, in ways that look
    # like SDK bugs rather than configuration.
    balance = Hiero::AccountBalanceQuery
              .new(account_id: client.operator_account_id)
              .execute(client)

    expect(balance.hbars).to be_positive
  end
end
