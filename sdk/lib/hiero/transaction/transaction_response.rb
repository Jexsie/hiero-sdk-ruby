# frozen_string_literal: true

module Hiero
  # What a node returns when it accepts a transaction for processing.
  #
  # Acceptance is not success. The node has checked the signature, the fee and the
  # shape of the request, and nothing more -- the transaction has not reached
  # consensus and may still fail there. {#receipt} is what waits for the outcome.
  class TransactionResponse
    attr_reader :transaction_id, :node_account_id, :transaction_hash

    def initialize(transaction_id:, node_account_id:, transaction_hash:)
      @transaction_id = transaction_id
      @node_account_id = node_account_id
      @transaction_hash = transaction_hash
      freeze
    end

    # Waits for consensus and returns the receipt.
    #
    # @param validate_status [Boolean] raise when the receipt is not SUCCESS.
    #   Pass false to inspect a failure without rescuing -- the transaction still
    #   reached consensus and was still charged for.
    def receipt(client, validate_status: true)
      TransactionReceiptQuery
        .new(transaction_id: @transaction_id, validate_status: validate_status)
        .execute(client)
    end

    def to_s = @transaction_id.to_s
    def inspect = "#<#{self.class} #{@transaction_id} node=#{@node_account_id}>"
  end
end
