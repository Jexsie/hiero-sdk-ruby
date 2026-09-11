# frozen_string_literal: true

RSpec.describe Hiero::Transaction do
  let(:key) { Hiero::PrivateKey.generate_ed25519 }
  let(:payer) { "0.0.1001" }

  def transfer
    Hiero::TransferTransaction.new
      .add_hbar_transfer("0.0.1001", Hiero::Hbar.new(-1))
      .add_hbar_transfer("0.0.1002", Hiero::Hbar.new(1))
  end

  def frozen_transfer(nodes: ["0.0.3"])
    tx = transfer
    tx.transaction_id = Hiero::TransactionId.generate(payer)
    tx.node_account_ids = nodes
    tx.freeze_with(nil)
  end

  describe "freezing" do
    it "fixes the id and nodes" do
      tx = frozen_transfer

      expect(tx).to be_frozen_body
      expect(tx.transaction_id).to be_a(Hiero::TransactionId)
    end

    it "refuses every setter afterwards" do
      # The signatures collected next cover exactly these bytes.
      tx = frozen_transfer

      expect { tx.transaction_memo = "late" }.to raise_error(Hiero::TransactionFrozenError)
      expect { tx.max_transaction_fee = 1 }.to raise_error(Hiero::TransactionFrozenError)
      expect { tx.add_hbar_transfer("0.0.9", 1) }.to raise_error(Hiero::TransactionFrozenError)
    end

    it "does not claim to be Ruby-frozen" do
      # #frozen? must stay honest: this object keeps mutating after freeze_with,
      # because signatures accumulate.
      tx = frozen_transfer

      expect(tx).to be_frozen_body
      expect(tx).not_to be_frozen
    end

    it "is idempotent" do
      tx = frozen_transfer
      id = tx.transaction_id

      expect { tx.freeze_with(nil) }.not_to raise_error
      expect(tx.transaction_id).to eq(id)
    end

    it "needs a payer from somewhere" do
      tx = transfer
      tx.node_account_ids = ["0.0.3"]

      expect { tx.freeze_with(nil) }.to raise_error(Hiero::Error, /transaction id or a client/)
    end

    it "takes the payer and nodes from a client" do
      client = Hiero::Client.for_network({ "a:1" => "0.0.3" })
      client.set_operator(payer, key)
      tx = transfer.freeze_with(client)

      expect(tx.transaction_id.account_id).to eq(Hiero::AccountId.from_string(payer))
      expect(tx.node_account_ids.to_a).to eq([Hiero::AccountId.new(num: 3)])
    end

    it "applies the client's default fee" do
      client = Hiero::Client.for_network({ "a:1" => "0.0.3" }, default_max_transaction_fee: Hiero::Hbar.new(7))
      client.set_operator(payer, key)

      expect(transfer.freeze_with(client).max_transaction_fee).to eq(Hiero::Hbar.new(7))
    end
  end

  describe "signing" do
    it "refuses before freezing, there being no bytes to sign" do
      expect { transfer.sign(key) }.to raise_error(Hiero::Error, /must be frozen/)
    end

    it "records a signer once" do
      tx = frozen_transfer.sign(key).sign(key)

      expect(tx.signatures.length).to eq(1)
      expect(tx).to be_signed_by(key.public_key)
    end

    it "produces signatures a public key verifies" do
      tx = frozen_transfer.sign(key)
      body = Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes).bodyBytes

      expect(key.public_key.verify(tx.signatures[key.public_key], body)).to be(true)
    end

    it "accepts a signature produced elsewhere" do
      # The multi-party workflow: ship the bytes out, sign offline, merge back.
      tx = frozen_transfer
      other = Hiero::PrivateKey.generate_ecdsa
      body = Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes).bodyBytes
      tx.add_signature(other.public_key, other.sign(body))

      expect(tx.signatures).to have_key(other.public_key)
    end

    it "puts each signature in the map under its key prefix" do
      tx = frozen_transfer.sign(key)
      signed = Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes)
      pair = signed.sigMap.sigPair.first

      expect(pair.pubKeyPrefix).to eq(key.public_key.to_bytes_raw)
      expect(pair.ed25519.bytesize).to eq(64)
    end

    it "uses the ECDSA field for an ECDSA key" do
      ecdsa = Hiero::PrivateKey.generate_ecdsa
      tx = frozen_transfer.sign(ecdsa)
      pair = Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes).sigMap.sigPair.first

      expect(pair.ECDSA_secp256k1.bytesize).to eq(64)
      expect(pair.ed25519).to be_empty
    end
  end

  describe "the signing matrix" do
    it "builds one body per node, each naming itself" do
      # Every node gets a body naming itself as nodeAccountID, so every node needs
      # its own signature -- one transaction is several messages.
      tx = frozen_transfer(nodes: ["0.0.3", "0.0.4", "0.0.5"]).sign(key)
      list = Proto::TransactionList.decode(tx.to_bytes).transaction_list

      nodes = list.map do |entry|
        body = Proto::TransactionBody.decode(Proto::SignedTransaction.decode(entry.signedTransactionBytes).bodyBytes)
        body.nodeAccountID.accountNum
      end

      expect(nodes).to eq([3, 4, 5])
    end

    it "signs each body separately, so signatures differ per node" do
      tx = frozen_transfer(nodes: ["0.0.3", "0.0.4"]).sign(key)
      list = Proto::TransactionList.decode(tx.to_bytes).transaction_list
      signatures = list.map { |e| Proto::SignedTransaction.decode(e.signedTransactionBytes).sigMap.sigPair.first.ed25519 }

      expect(signatures.uniq.length).to eq(2)
    end

    it "sends the body for whichever node the current attempt is going to" do
      tx = frozen_transfer(nodes: ["0.0.3", "0.0.4"]).sign(key)

      first = Proto::TransactionBody.decode(
        Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes).bodyBytes
      )
      tx.node_account_ids.advance
      second = Proto::TransactionBody.decode(
        Proto::SignedTransaction.decode(tx.make_request.signedTransactionBytes).bodyBytes
      )

      expect([first.nodeAccountID.accountNum, second.nodeAccountID.accountNum]).to eq([3, 4])
    end
  end

  describe "serialization" do
    it "round-trips through bytes" do
      tx = frozen_transfer.sign(key)
      restored = described_class.from_bytes(tx.to_bytes)

      expect(restored).to be_a(Hiero::TransferTransaction)
      expect(restored.hbar_transfers.values.map(&:to_tinybars)).to eq([-100_000_000, 100_000_000])
    end

    it "dispatches through the registry rather than importing every subclass" do
      expect(described_class::REGISTRY[:cryptoTransfer]).to eq(Hiero::TransferTransaction)
    end

    it "keys the registry on protobuf's own casing" do
      # HAPI declares most fields camelCase, so body.data reports :cryptoTransfer.
      # Guessing :crypto_transfer here would fail only at deserialization time.
      body = Proto::TransactionBody.new(cryptoTransfer: Proto::CryptoTransferTransactionBody.new)

      expect(described_class::REGISTRY).to have_key(body.data)
    end

    it "refuses to serialise before freezing" do
      expect { transfer.to_bytes }.to raise_error(Hiero::Error, /must be frozen/)
    end

    it "reports an unknown transaction type clearly" do
      body = Proto::TransactionBody.encode(Proto::TransactionBody.new(freeze: Proto::FreezeTransactionBody.new))
      signed = Proto::SignedTransaction.encode(Proto::SignedTransaction.new(bodyBytes: body))
      bytes = Proto::Transaction.encode(Proto::Transaction.new(signedTransactionBytes: signed))

      expect { described_class.from_bytes(bytes) }.to raise_error(Hiero::Error, /unsupported transaction type/)
    end
  end

  describe "precheck statuses" do
    def state_for(code)
      response = Proto::TransactionResponse.new(nodeTransactionPrecheckCode: code)
      frozen_transfer.execution_state(nil, response).last
    end

    it "finishes on OK" do
      expect(state_for(:OK)).to eq(:finished)
    end

    it "retries the transient ones" do
      %i[BUSY UNKNOWN PLATFORM_NOT_ACTIVE PLATFORM_TRANSACTION_NOT_CREATED INVALID_NODE_ACCOUNT].each do |code|
        expect(state_for(code)).to eq(:retry), code.to_s
      end
    end

    it "fails on anything else" do
      expect(state_for(:INSUFFICIENT_PAYER_BALANCE)).to eq(:error)
    end
  end
end
