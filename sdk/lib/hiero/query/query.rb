# frozen_string_literal: true

module Hiero
  # Base class for reads from a consensus node.
  #
  # Most queries are paid: the node quotes a price, the client attaches a signed
  # transfer, and only then does it answer. A few are free, and this class
  # currently implements only the free path -- payment orchestration arrives with
  # the transaction layer, since it needs a signed CryptoTransfer to attach.
  #
  # {#payment_required?} is what separates the two, so a free query is a query
  # that says so rather than a special case threaded through the base class.
  class Query < Executable
    # The status of a query is carried in its response header, not in a top-level
    # field, and every response type nests that header differently -- hence
    # {#response_header}, which subclasses implement.
    def payment_required? = true

    def before_execute(client)
      return unless payment_required?

      raise NotImplementedError,
            "paid queries are not implemented yet; #{self.class} must override #payment_required?"
    end

    def execution_state(_request, response)
      status = Status[response_header(response).nodeTransactionPrecheckCode]

      state =
        case status
        when Status::OK then :finished
        when Status::BUSY, Status::PLATFORM_NOT_ACTIVE, Status::PLATFORM_TRANSACTION_NOT_CREATED,
             Status::INVALID_NODE_ACCOUNT then :retry
        else :error
        end

      [status, state]
    end

    def map_status_error(_request, response, node_account_id)
      PrecheckStatusError.new(
        status: Status[response_header(response).nodeTransactionPrecheckCode],
        node_account_id: node_account_id
      )
    end

    # @return [Proto::ResponseHeader] the header nested inside this response type
    def response_header(_response) = raise(NotImplementedError, "#{self.class} must implement #response_header")

    private

    # A free query still has to send a header; it simply carries no payment.
    def query_header
      ::Proto::QueryHeader.new(responseType: :ANSWER_ONLY)
    end
  end
end
