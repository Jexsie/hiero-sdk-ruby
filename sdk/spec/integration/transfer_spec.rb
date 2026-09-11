# frozen_string_literal: true

# The whole loop against a real node: freeze, sign, submit, poll for consensus,
# and see the balance move. Everything the unit specs verify in pieces, verified
# once as a thing that actually works.
RSpec.describe "transferring hbar on a live network", :integration, :operator do
  let(:client) { Solo.client }
  let(:payer) { client.operator_account_id }

  after { client.close }

  def balance_of(account_id)
    Hiero::AccountBalanceQuery.new(account_id: account_id).execute(client).hbars
  end

  it "moves hbar and reports SUCCESS" do
    # A fresh account, not the node account. The node earns fees from everything
    # else running, so its balance moves by more than this transfer sends and the
    # delta cannot be asserted exactly -- which showed up as an intermittent
    # failure of exactly one query fee.
    recipient = Hiero::AccountCreateTransaction
                .new(key: Hiero::PrivateKey.generate_ed25519.public_key)
                .execute(client).receipt(client).account_id
    before = balance_of(recipient)

    response = Hiero::TransferTransaction.new
                                                  .add_hbar_transfer(payer, Hiero::Hbar.new(-1))
                                                  .add_hbar_transfer(recipient, Hiero::Hbar.new(1))
                                                  .set_transaction_memo("hiero-sdk-ruby integration")
                                                  .execute(client)

    expect(response.transaction_id.account_id).to eq(payer)
    expect(response.transaction_hash.bytesize).to eq(48) # SHA-384

    receipt = response.receipt(client)

    expect(receipt).to be_success
    expect(receipt.status).to eq(Hiero::Status::SUCCESS)
    expect(balance_of(recipient) - before).to eq(Hiero::Hbar.new(1))
  end

  it "charges the payer a fee on top of the amount sent" do
    # The payer loses the transfer plus the network's fee, so the two sides are
    # never symmetrical.
    before = balance_of(payer)

    Hiero::TransferTransaction.new
                                       .add_hbar_transfer(payer, Hiero::Hbar.new(-1))
                                       .add_hbar_transfer(Solo::NODE_ACCOUNT, Hiero::Hbar.new(1))
                                       .execute(client)
                                       .receipt(client)

    spent = before - balance_of(payer)

    expect(spent).to be > Hiero::Hbar.new(1)
  end

  it "signs with the operator without being asked" do
    # No explicit #sign call: before_execute signs with the client's operator,
    # which is what makes the common case a one-liner.
    receipt = Hiero::TransferTransaction.new
                                                 .add_hbar_transfer(payer, Hiero::Hbar.new(-1))
                                                 .add_hbar_transfer(Solo::NODE_ACCOUNT, Hiero::Hbar.new(1))
                                                 .execute(client)
                                                 .receipt(client)

    expect(receipt).to be_success
  end

  it "survives a round trip through bytes before being sent" do
    # The multi-party workflow: freeze, serialise, ship elsewhere, sign, submit.
    tx = Hiero::TransferTransaction.new
                                            .add_hbar_transfer(payer, Hiero::Hbar.new(-1))
                                            .add_hbar_transfer(Solo::NODE_ACCOUNT, Hiero::Hbar.new(1))
                                            .freeze_with(client)

    restored = Hiero::Transaction.from_bytes(tx.to_bytes)
    restored.transaction_id = tx.transaction_id
    restored.node_account_ids = tx.node_account_ids.to_a
    restored.freeze_with(client)

    expect(restored.execute(client).receipt(client)).to be_success
  end

  describe "a transfer the sender cannot afford" do
    # The node accepts this at precheck -- it does not check balances there -- and
    # it fails at consensus instead. That is precisely the distinction between
    # PrecheckStatusError and ReceiptStatusError, and it costs the payer a fee.
    let(:transaction) do
      Hiero::TransferTransaction.new
                                         .add_hbar_transfer(Solo::NODE_ACCOUNT, Hiero::Hbar.new(-100_000_000))
                                         .add_hbar_transfer(payer, Hiero::Hbar.new(100_000_000))
    end

    it "is accepted by the node" do
      expect { transaction.execute(client) }.not_to raise_error
    end

    it "fails at consensus, and the receipt says why" do
      response = transaction.execute(client)
      receipt = response.receipt(client, validate_status: false)

      expect(receipt).not_to be_success
      expect(receipt.status).not_to eq(Hiero::Status::SUCCESS)
    end

    it "raises by default, because a failed transaction is usually a surprise" do
      response = transaction.execute(client)

      expect { response.receipt(client) }.to raise_error(Hiero::ReceiptStatusError) do |error|
        expect(error.transaction_id).to eq(response.transaction_id)
      end
    end
  end

  it "keeps polling until a receipt exists" do
    # The receipt is not available the instant a node accepts the transaction, so
    # this only passes because the query treats an absent receipt as "ask again".
    response = Hiero::TransferTransaction.new
                                                  .add_hbar_transfer(payer, Hiero::Hbar.new(-1))
                                                  .add_hbar_transfer(Solo::NODE_ACCOUNT, Hiero::Hbar.new(1))
                                                  .execute(client)

    expect(response.receipt(client)).to be_success
  end
end

RSpec.describe "creating an account on a live network", :integration, :operator do
  let(:client) { Solo.client }

  after { client.close }

  it "creates a funded account and reports its number on the receipt" do
    # The account's number is not known until consensus, which is why it arrives
    # on the receipt rather than from the transaction object.
    key = Hiero::PrivateKey.generate_ed25519

    receipt = Hiero::AccountCreateTransaction
              .new(key: key.public_key, initial_balance: Hiero::Hbar.new(1))
              .execute(client)
              .receipt(client)

    expect(receipt).to be_success
    expect(receipt.account_id).to be_a(Hiero::AccountId)

    info = Hiero::AccountInfoQuery.new(account_id: receipt.account_id).execute(client)
    expect(info.balance).to eq(Hiero::Hbar.new(1))
    expect(info.key).to eq(key.public_key)
  end

  it "creates an account controlled by a key list" do
    a = Hiero::PrivateKey.generate_ed25519
    b = Hiero::PrivateKey.generate_ecdsa
    list = Hiero::KeyList.with_threshold(1, a.public_key, b.public_key)

    receipt = Hiero::AccountCreateTransaction.new(key: list).execute(client).receipt(client)
    info = Hiero::AccountInfoQuery.new(account_id: receipt.account_id).execute(client)

    expect(info.key).to eq(list)
  end

  it "creates an account the new key can then spend from" do
    # Proves the created account is genuinely controlled by the key given, not
    # merely recorded as such.
    key = Hiero::PrivateKey.generate_ed25519
    receipt = Hiero::AccountCreateTransaction
              .new(key: key.public_key, initial_balance: Hiero::Hbar.new(2))
              .execute(client).receipt(client)

    owned = Hiero::Client.for_network(Solo.network, local: true, request_timeout: 15.0)
    owned.set_operator(receipt.account_id, key)

    spend = Hiero::TransferTransaction.new
                                      .add_hbar_transfer(receipt.account_id, Hiero::Hbar.new(-1))
                                      .add_hbar_transfer(Solo::TREASURY, Hiero::Hbar.new(1))
                                      .execute(owned)
                                      .receipt(owned)

    expect(spend).to be_success
  ensure
    owned&.close
  end
end
