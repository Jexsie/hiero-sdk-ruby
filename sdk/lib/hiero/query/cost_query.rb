# frozen_string_literal: true

module Hiero
  # Asks a node what another query would cost, without running it.
  #
  # It sends the wrapped query's own body -- the price depends on what is being
  # asked -- with the response type set to COST_ANSWER, and reads the figure out
  # of the response header rather than the body.
  #
  # The enquiry is answered free of charge, but the node still expects a payment
  # transaction in the header to pass validation. It is addressed to account zero
  # with nothing in it and is left unsigned: the node checks that one is present,
  # not that it is worth anything.
  class CostQuery < Executable
    ZERO_NODE = "0.0.0"

    def initialize(query)
      super()
      @query = query
      self.node_account_ids = query.node_account_ids.to_a
    end

    def before_execute(client)
      @query.payment_transaction_id = TransactionId.generate(
        client.operator_account_id || AccountId.new(num: 0)
      )
    end

    def make_request
      header = ::Proto::QueryHeader.new(
        responseType: :COST_ANSWER,
        payment: @query.payment_transaction(ZERO_NODE, Hbar::ZERO, operator: nil)
      )

      @query.build_query(header)
    end

    def call(channel, request, deadline:) = @query.call(channel, request, deadline: deadline)

    def execution_state(request, response) = @query.execution_state(request, response)
    def map_status_error(request, response, node_account_id) = @query.map_status_error(request, response, node_account_id)

    # The answer is in the header, not the body: this is a price, not a result.
    def map_response(response, _node_account_id, _request)
      Hbar.from_tinybars(@query.response_header(response).cost)
    end
  end
end
