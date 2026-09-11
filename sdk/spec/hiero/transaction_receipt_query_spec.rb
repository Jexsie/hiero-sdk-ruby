# frozen_string_literal: true

RSpec.describe Hiero::TransactionReceiptQuery do
  let(:transaction_id) { Hiero::TransactionId.generate("0.0.1001") }

  def response(precheck: :OK, receipt: :SUCCESS)
    Proto::Response.new(
      transactionGetReceipt: Proto::TransactionGetReceiptResponse.new(
        header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: precheck),
        receipt: Proto::TransactionReceipt.new(status: receipt)
      )
    )
  end

  it "is free, so finding out what happened never costs anything" do
    expect(described_class.new(transaction_id: transaction_id).payment_required?).to be(false)
  end

  it "needs a transaction id" do
    client = Hiero::Client.for_network({ "a:1" => "0.0.3" })

    expect { described_class.new.execute(client) }.to raise_error(Hiero::Error, /needs a transaction_id/)
  end

  describe "polling" do
    subject(:query) { described_class.new(transaction_id: transaction_id) }

    # This is the one request whose retrying is driven by the answer rather than
    # by a failure: a node that has not yet seen the transaction returns
    # RECEIPT_NOT_FOUND with a perfectly successful precheck.
    it "keeps asking while the receipt is not there yet" do
      %i[RECEIPT_NOT_FOUND RECORD_NOT_FOUND UNKNOWN OK].each do |pending|
        expect(query.execution_state(nil, response(receipt: pending)).last).to eq(:retry), pending.to_s
      end
    end

    it "finishes once the receipt says something" do
      expect(query.execution_state(nil, response(receipt: :SUCCESS)).last).to eq(:finished)
    end

    it "finishes on a failed receipt too, that being an answer" do
      state = query.execution_state(nil, response(receipt: :INSUFFICIENT_ACCOUNT_BALANCE))

      expect(state).to eq([Hiero::Status::INSUFFICIENT_ACCOUNT_BALANCE, :finished])
    end

    it "keeps asking when the node returns no receipt at all" do
      # Not the same as a receipt saying RECEIPT_NOT_FOUND: the field is simply
      # absent, which is the most common answer this query gets while polling.
      bare = Proto::Response.new(
        transactionGetReceipt: Proto::TransactionGetReceiptResponse.new(
          header: Proto::ResponseHeader.new(nodeTransactionPrecheckCode: :OK)
        )
      )

      expect(query.execution_state(nil, bare)).to eq([Hiero::Status::RECEIPT_NOT_FOUND, :retry])
    end

    it "still retries a busy node" do
      expect(query.execution_state(nil, response(precheck: :BUSY)).last).to eq(:retry)
    end

    it "fails on a precheck error" do
      expect(query.execution_state(nil, response(precheck: :INVALID_TRANSACTION_ID)).last).to eq(:error)
    end
  end

  describe "mapping the receipt" do
    it "raises when the transaction failed at consensus" do
      # It reached consensus and was charged for, which is why this is a distinct
      # error from a precheck rejection.
      query = described_class.new(transaction_id: transaction_id)

      expect { query.map_response(response(receipt: :INSUFFICIENT_ACCOUNT_BALANCE), nil, nil) }
        .to raise_error(Hiero::ReceiptStatusError, /reached consensus and failed/)
    end

    it "returns the failed receipt instead when asked not to validate" do
      query = described_class.new(transaction_id: transaction_id, validate_status: false)
      receipt = query.map_response(response(receipt: :INSUFFICIENT_ACCOUNT_BALANCE), nil, nil)

      expect(receipt.status).to eq(Hiero::Status::INSUFFICIENT_ACCOUNT_BALANCE)
      expect(receipt).not_to be_success
    end

    it "returns a successful receipt" do
      receipt = described_class.new(transaction_id: transaction_id)
                               .map_response(response, nil, nil)

      expect(receipt).to be_success
    end
  end

  describe Hiero::TransactionReceipt do
    it "surfaces the entity a transaction created" do
      proto = Proto::TransactionReceipt.new(status: :SUCCESS,
                                            accountID: Proto::AccountID.new(accountNum: 5005))
      receipt = described_class.from_protobuf(proto)

      expect(receipt.account_id).to eq(Hiero::AccountId.new(num: 5005))
      expect(receipt.token_id).to be_nil
    end

    it "leaves entity fields nil for a transaction that creates nothing" do
      receipt = described_class.from_protobuf(Proto::TransactionReceipt.new(status: :SUCCESS))

      expect([receipt.account_id, receipt.file_id, receipt.token_id, receipt.topic_id]).to all(be_nil)
    end

    it "is immutable" do
      expect(described_class.from_protobuf(Proto::TransactionReceipt.new(status: :SUCCESS))).to be_frozen
    end
  end
end
