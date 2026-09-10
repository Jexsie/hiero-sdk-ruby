# frozen_string_literal: true

module Hiero
  # Which transport failures are worth trying another node for.
  #
  # The distinction matters in both directions. Retrying something permanent
  # wastes a whole attempt budget on a request that can never succeed; failing on
  # something transient throws away a request that the next node would have
  # accepted.
  module Retryable
    # gRPC reports a connection reset as INTERNAL with the detail in a message
    # string, so the string is the only thing that distinguishes "this connection
    # died, try again" from a genuine server-side error.
    RST_STREAM = /\brst[^0-9a-zA-Z]stream\b/i

    module_function

    # @param error [Exception]
    # @return [Boolean]
    def grpc?(error)
      case error
      when defined?(GRPC) ? GRPC::Unavailable : nil then true
      when defined?(GRPC) ? GRPC::ResourceExhausted : nil then true
      when defined?(GRPC) ? GRPC::DeadlineExceeded : nil then true
      when defined?(GRPC) ? GRPC::Internal : nil then RST_STREAM.match?(error.details.to_s)
      else false
      end
    end
  end
end
