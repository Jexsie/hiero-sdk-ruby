# frozen_string_literal: true

module Hiero
  # The retry loop every request runs through.
  #
  # Subclasses answer four questions and this class owns everything else --
  # attempts, node rotation, backoff, deadlines:
  #
  #   1. what protobuf message am I?        {#make_request}
  #   2. which gRPC method sends me?        {#call}
  #   3. done, retry, or failed?            {#execution_state}
  #   4. how do I become a Ruby object?     {#map_response}
  #
  # == Three different timeouts
  #
  #   grpc_deadline    one call. Exceeding it is retryable, and the next node may
  #                    well answer.
  #   request_timeout  the whole of #execute including retries. A ceiling on how
  #                    long a caller can be kept waiting.
  #   max_attempts     how many tries, regardless of how fast they fail.
  #
  # The per-call deadline is passed to gRPC itself rather than raced against a
  # timer. The JavaScript SDK has to run Promise.race with its own timer because a
  # consensus node can hold a connection open and answer neither way; gRPC's own
  # deadline is enforced in its C core and covers that case with nothing to leak.
  #
  # Timing is measured on {Clock}, which is monotonic. Ruby's Timeout is
  # deliberately not used anywhere here: it raises asynchronously into whatever
  # happens to be running, which can leave gRPC and OpenSSL in an inconsistent
  # state.
  class Executable
    attr_accessor :max_attempts, :min_backoff, :max_backoff, :request_timeout, :grpc_deadline
    attr_reader :node_account_ids

    def initialize
      @node_account_ids = CircularList.new
      @max_attempts = nil
      @min_backoff = nil
      @max_backoff = nil
      @request_timeout = nil
      @grpc_deadline = nil
    end

    # --- the contract subclasses implement --------------------------------------

    # Runs once before the loop. Where a transaction freezes and signs, and a
    # query works out what it must pay.
    def before_execute(client); end

    # @return [Object] the protobuf message for this attempt
    def make_request = raise(NotImplementedError, "#{self.class} must implement #make_request")

    # @param deadline [Time] passed to gRPC, which enforces it
    def call(_channel, _request, deadline:) = raise(NotImplementedError, "#{self.class} must implement #call")

    # @return [Array(Status, Symbol)] the status, and :finished, :retry or :error
    def execution_state(_request, _response) = raise(NotImplementedError, "#{self.class} must implement #execution_state")

    # @return [Object] the user-facing result
    def map_response(_response, _node_account_id, _request) = raise(NotImplementedError, "#{self.class} must implement #map_response")

    # @return [Exception] the error to raise for a failed status
    def map_status_error(_request, _response, _node_account_id) = raise(NotImplementedError, "#{self.class} must implement #map_status_error")

    # @return [Boolean] whether a transport error is worth another node
    def retry_exceptionally?(error) = Retryable.grpc?(error)

    # --- the loop ---------------------------------------------------------------

    # @param client [Client]
    # @param timeout [Float, nil] overrides the client's request_timeout
    # @return [Object] whatever {#map_response} returns
    def execute(client, timeout: nil)
      client.ensure_open!
      inherit_defaults_from(client)
      before_execute(client)
      choose_nodes(client) if @node_account_ids.empty?

      deadline_at = Clock.now + (timeout || @request_timeout)
      last_error = nil
      attempt = 0

      while attempt < @max_attempts
        if Clock.now >= deadline_at
          raise MaxAttemptsError.timeout(attempt, @request_timeout, last_error, @node_account_ids.current)
        end

        node_account_id = @node_account_ids.current
        node = client.network.node_for(node_account_id)

        # A node the request is pinned to but the client no longer knows about.
        # Skip rather than fail: the other nodes in the list may still work.
        if node.nil?
          @node_account_ids.advance
          attempt += 1
          next
        end

        request = make_request
        @node_account_ids.advance

        begin
          response = call(node.channel, request, deadline: call_deadline(deadline_at))
        rescue StandardError => e
          raise e unless retry_exceptionally?(e)

          client.network.increase_backoff(node)
          last_error = e
          attempt += 1
          sleep_before_retry(attempt, client)
          next
        end

        client.network.decrease_backoff(node)
        status, state = execution_state(request, response)

        case state
        when :finished
          return map_response(response, node_account_id, request)
        when :error
          raise map_status_error(request, response, node_account_id)
        when :retry
          last_error = map_status_error(request, response, node_account_id)
          attempt += 1
          sleep_before_retry(attempt, client)
        else
          raise Error, "#{self.class}#execution_state returned #{state.inspect}"
        end
      end

      raise MaxAttemptsError.exhausted(@max_attempts, last_error, @node_account_ids.current)
    end

    # @param ids [Array] the nodes this request may be sent to
    def node_account_ids=(ids)
      @node_account_ids.items = Array(ids).map { |id| AccountId.coerce(id) }
    end

    private

    # Anything not set on the request itself comes from the client, so a caller can
    # override one knob for one request without disturbing the rest.
    def inherit_defaults_from(client)
      @max_attempts ||= client.max_attempts
      @min_backoff ||= client.min_backoff
      @max_backoff ||= client.max_backoff
      @request_timeout ||= client.request_timeout
      @grpc_deadline ||= client.grpc_deadline
    end

    def choose_nodes(client)
      nodes = client.network.healthiest(client.network.account_ids.length)
      raise Error, "this client has no nodes to send to" if nodes.empty?

      @node_account_ids.items = nodes.map(&:account_id)
    end

    # The earlier of the per-call deadline and what is left of the overall budget,
    # so a single slow call cannot overshoot the caller's timeout.
    def call_deadline(deadline_at)
      seconds = [@grpc_deadline, deadline_at - Clock.now].min
      Time.now + [seconds, 0.0].max
    end

    # min_backoff * 2**attempt, capped. Flat on a local network, where a node
    # answers instantly or not at all and waiting longer achieves nothing.
    def backoff_for(attempt, client)
      return @min_backoff if client.local?

      [@min_backoff * (2**(attempt - 1)), @max_backoff].min
    end

    def sleep_before_retry(attempt, client) = sleep(backoff_for(attempt, client))
  end
end
