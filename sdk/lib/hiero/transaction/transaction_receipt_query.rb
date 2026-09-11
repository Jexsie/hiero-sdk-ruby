# frozen_string_literal: true

module Hiero
  # Waits for a transaction to reach consensus and reports the outcome.
  #
  # This is the one request whose retrying is driven by the *answer* rather than
  # by a failure. A node that has not yet seen the transaction returns
  # RECEIPT_NOT_FOUND with a perfectly successful precheck status, so the polling
  # loop that makes `response.receipt(client)` block until consensus is expressed
  # by treating that inner status as retryable.
  #
  # Free, so that finding out what happened never costs anything.
  class TransactionReceiptQuery < Query
    # Inner statuses meaning "ask again", as opposed to "the answer is no".
    PENDING = [
      Status::RECEIPT_NOT_FOUND,
      Status::RECORD_NOT_FOUND,
      Status::UNKNOWN,
      Status::OK
    ].freeze

    attr_reader :transaction_id

    def initialize(transaction_id: nil, validate_status: true)
      super()
      @transaction_id = transaction_id
      @validate_status = validate_status
    end

    def transaction_id=(value)
      @transaction_id = value.is_a?(TransactionId) ? value : TransactionId.from_string(value.to_s)
    end

    def set_transaction_id(value) = (self.transaction_id = value; self)

    def payment_required? = false

    def before_execute(_client)
      raise Error, "a TransactionReceiptQuery needs a transaction_id" if @transaction_id.nil?
    end

    def make_request
      ::Proto::Query.new(
        transactionGetReceipt: ::Proto::TransactionGetReceiptQuery.new(
          header: query_header, transactionID: @transaction_id.to_protobuf
        )
      )
    end

    def call(channel, request, deadline:)
      channel.crypto.get_transaction_receipts(request, deadline: deadline)
    end

    def response_header(response) = response.transactionGetReceipt.header

    # Unlike every other query, the precheck status being OK does not mean the
    # answer is ready -- it means the node accepted the question.
    def execution_state(_request, response)
      precheck = Status[response_header(response).nodeTransactionPrecheckCode]

      unless PENDING.include?(precheck)
        return [precheck, %i[BUSY PLATFORM_NOT_ACTIVE].include?(precheck.name) ? :retry : :error]
      end

      # A node that has not seen the transaction yet answers with no receipt at
      # all rather than one saying RECEIPT_NOT_FOUND, so the absent case has to be
      # treated as "ask again" too. Reading .status straight off it crashes on the
      # single most common response this query gets.
      receipt = response.transactionGetReceipt.receipt
      return [Status::RECEIPT_NOT_FOUND, :retry] if receipt.nil?

      receipt_status = Status[receipt.status]
      [receipt_status, PENDING.include?(receipt_status) ? :retry : :finished]
    end

    # The receipt is returned whatever it says. A failed transaction still reached
    # consensus and was still charged for, so it is an answer, not an error --
    # unless the caller asked for the failure to be raised.
    def map_response(response, _node_account_id, _request)
      receipt = TransactionReceipt.from_protobuf(response.transactionGetReceipt.receipt)
      @validate_status ? receipt.validate_status!(@transaction_id) : receipt
    end
  end
end
