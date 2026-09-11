# frozen_string_literal: true

RSpec.describe Hiero::Query do
  let(:key) { Hiero::PrivateKey.generate_ed25519 }

  def client(**options)
    Hiero::Client.for_network({ "a:1" => "0.0.3", "b:2" => "0.0.4" }, **options)
                 .set_operator("0.0.1001", key)
  end

  def paid = Hiero::AccountInfoQuery.new(account_id: "0.0.2")

  def payment_body(query)
    header = query.make_request.cryptoGetInfo.header
    Proto::TransactionBody.decode(
      Proto::SignedTransaction.decode(header.payment.signedTransactionBytes).bodyBytes
    )
  end

  it "charges by default, and free queries opt out" do
    expect(paid.payment_required?).to be(true)
    expect(Hiero::AccountBalanceQuery.new(account_id: 2).payment_required?).to be(false)
    expect(Hiero::TransactionReceiptQuery.new(transaction_id: nil).payment_required?).to be(false)
  end

  describe "an explicit price" do
    it "skips the cost enquiry entirely" do
      # Worth doing in a hot path where the price is known: it saves a whole
      # round trip to the node.
      query = paid
      query.query_payment = Hiero::Hbar.new(1)
      expect(query).not_to receive(:cost)

      query.before_execute(client)

      expect(query.query_payment).to eq(Hiero::Hbar.new(1))
    end

    it "is what the payment actually carries" do
      query = paid
      query.query_payment = Hiero::Hbar.from_tinybars(12_345)
      query.before_execute(client)

      amounts = payment_body(query).cryptoTransfer.transfers.accountAmounts

      expect(amounts.map(&:amount).sort).to eq([-12_345, 12_345])
    end
  end

  describe "discovering the price" do
    it "adds ten percent headroom to the quote" do
      # Fees move with the exchange rate between the two round trips, and a
      # payment a hair under the real cost is rejected outright.
      query = paid
      allow(query).to receive(:cost).and_return(Hiero::Hbar.from_tinybars(1_000))
      query.before_execute(client)

      expect(query.query_payment).to eq(Hiero::Hbar.from_tinybars(1_000))
    end

    it "rounds the headroom up, never down" do
      expect(described_class::COST_HEADROOM).to eq(Rational(11, 10))
      expect((7 * described_class::COST_HEADROOM).ceil).to eq(8)
    end

    it "refuses to pay more than the ceiling" do
      query = paid
      allow(query).to receive(:cost).and_return(Hiero::Hbar.new(5))

      expect { query.before_execute(client(max_query_payment: Hiero::Hbar.new(1))) }
        .to raise_error(Hiero::MaxQueryPaymentExceededError) do |error|
          expect(error.cost).to eq(Hiero::Hbar.new(5))
          expect(error.maximum).to eq(Hiero::Hbar.new(1))
        end
    end

    it "raises before anything is signed" do
      # The price is discovered first; the payment is only built once it is under
      # the ceiling, so an over-budget query costs nothing.
      query = paid
      allow(query).to receive(:cost).and_return(Hiero::Hbar.new(5))

      expect { query.before_execute(client(max_query_payment: Hiero::Hbar.new(1))) }
        .to raise_error(Hiero::MaxQueryPaymentExceededError)

      # No payment was built, so nothing was signed and nothing can be spent.
      expect(query.make_request.cryptoGetInfo.header.payment).to be_nil
    end

    it "lets one query override the client's ceiling" do
      query = paid
      query.max_query_payment = Hiero::Hbar.new(10)
      allow(query).to receive(:cost).and_return(Hiero::Hbar.new(5))

      expect { query.before_execute(client(max_query_payment: Hiero::Hbar.new(1))) }.not_to raise_error
    end
  end

  describe "the payment transaction" do
    subject(:query) do
      q = paid
      q.query_payment = Hiero::Hbar.new(1)
      q.before_execute(client)
      q
    end

    it "moves the price from the operator to the node" do
      amounts = payment_body(query).cryptoTransfer.transfers.accountAmounts.to_h { |a| [a.accountID.accountNum, a.amount] }

      expect(amounts[1001]).to eq(-100_000_000)
      expect(amounts.values.sum).to eq(0)
    end

    it "names the node the current attempt is going to" do
      # One payment per node, because each names its own node in the body it
      # signs -- the same reason a transaction is several messages.
      first = payment_body(query).nodeAccountID.accountNum
      query.node_account_ids.advance
      second = payment_body(query).nodeAccountID.accountNum

      expect(first).not_to eq(second)
    end

    it "is signed by the operator" do
      header = query.make_request.cryptoGetInfo.header
      signed = Proto::SignedTransaction.decode(header.payment.signedTransactionBytes)
      pair = signed.sigMap.sigPair.first

      expect(pair.pubKeyPrefix).to eq(key.public_key.to_bytes_raw)
      expect(key.public_key.verify(pair.ed25519, signed.bodyBytes)).to be(true)
    end

    it "asks for the answer, not the price" do
      expect(query.make_request.cryptoGetInfo.header.responseType).to eq(:ANSWER_ONLY)
    end
  end

  it "needs an operator to pay with" do
    anonymous = Hiero::Client.for_network({ "a:1" => "0.0.3" })

    expect { paid.before_execute(anonymous) }.to raise_error(Hiero::Error, /needs a client with an operator/)
  end

  it "attaches no payment to a free query" do
    query = Hiero::AccountBalanceQuery.new(account_id: "0.0.2")
    query.before_execute(client)

    expect(query.make_request.cryptogetAccountBalance.header.payment).to be_nil
  end
end

RSpec.describe Hiero::CostQuery do
  let(:key) { Hiero::PrivateKey.generate_ed25519 }
  let(:client) { Hiero::Client.for_network({ "a:1" => "0.0.3" }).set_operator("0.0.1001", key) }
  let(:inner) { Hiero::AccountInfoQuery.new(account_id: "0.0.2") }

  subject(:cost_query) do
    inner.node_account_ids = ["0.0.3"]
    q = described_class.new(inner)
    q.before_execute(client)
    q
  end

  it "sends the wrapped query's own body, the price depending on what is asked" do
    expect(cost_query.make_request.cryptoGetInfo.accountID.accountNum).to eq(2)
  end

  it "asks for the price rather than the answer" do
    expect(cost_query.make_request.cryptoGetInfo.header.responseType).to eq(:COST_ANSWER)
  end

  describe "the placeholder payment" do
    # The enquiry is free, but the node still expects a payment in the header to
    # pass validation. It checks that one is present, not that it is worth
    # anything.
    let(:header) { cost_query.make_request.cryptoGetInfo.header }
    let(:signed) { Proto::SignedTransaction.decode(header.payment.signedTransactionBytes) }

    it "is present" do
      expect(header.payment).not_to be_nil
    end

    it "is addressed to account zero and carries nothing" do
      body = Proto::TransactionBody.decode(signed.bodyBytes)

      expect(body.nodeAccountID.accountNum).to eq(0)
      expect(body.cryptoTransfer.transfers.accountAmounts.map(&:amount)).to all(eq(0))
    end

    it "is unsigned" do
      expect(signed.sigMap.sigPair).to be_empty
    end
  end

  it "reads the price out of the header, not the body" do
    response = Proto::Response.new(
      cryptoGetInfo: Proto::CryptoGetInfoResponse.new(
        header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: :OK, cost: 4_242)
      )
    )

    expect(cost_query.map_response(response, nil, nil)).to eq(Hiero::Hbar.from_tinybars(4_242))
  end
end
