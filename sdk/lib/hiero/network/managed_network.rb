# frozen_string_literal: true

module Hiero
  module Network
    # A pool of nodes and the health bookkeeping over it.
    #
    # == Locking
    #
    # The lock guards pool membership and health only, and is never held across a
    # network call. {#node_for} picks a node and returns; the caller then makes its
    # request with no lock held, and reports the outcome back afterwards. Holding
    # the lock for the duration of an RPC would serialise every thread in the
    # process behind the slowest node.
    #
    # A Monitor rather than a Mutex because it is reentrant: {#node_for} readmits
    # nodes as its first act, and both take the lock.
    class ManagedNetwork
      # Off by default -- see {Node#dead?}.
      DEFAULT_MAX_NODE_ATTEMPTS = -1

      attr_reader :max_node_attempts

      def initialize(max_node_attempts: DEFAULT_MAX_NODE_ATTEMPTS)
        @max_node_attempts = max_node_attempts
        @by_account = {}  # AccountId => [Node]
        @nodes = []
        @mutex = Monitor.new
      end

      # Replaces the pool wholesale.
      #
      # @param addresses [Hash{String => AccountId}] "host:port" => node account
      def replace(addresses)
        @mutex.synchronize do
          close
          @by_account = Hash.new { |h, k| h[k] = [] }
          @nodes = addresses.map do |address, account_id|
            node = Node.new(address: address, account_id: account_id)
            @by_account[node.account_id] << node
            node
          end
          self
        end
      end

      def nodes = @mutex.synchronize { @nodes.dup }
      def account_ids = @mutex.synchronize { @by_account.keys }
      def empty? = @mutex.synchronize { @nodes.empty? }
      def include?(account_id) = @mutex.synchronize { @by_account.key?(AccountId.coerce(account_id)) }

      # @param account_id [AccountId, nil] resolve this account, or any healthy node
      # @return [Node, nil]
      def node_for(account_id = nil)
        @mutex.synchronize do
          readmit!

          candidates =
            if account_id
              @by_account.fetch(AccountId.coerce(account_id), [])
            else
              healthy_nodes
            end

          # An account may have several addresses behind it -- a node reachable
          # through more than one proxy. Prefer a healthy one; fall back to any,
          # so that a caller pinned to one account still gets something to try.
          (candidates.select { |node| node.healthy?(now) }.sample || candidates.sample)
            &.tap(&:record_use!)
        end
      end

      # @return [Array<Node>] up to `count` distinct healthy nodes, sampled without
      #   replacement. Used at transaction freeze time to choose the node set a
      #   transaction will be signed for.
      def healthiest(count)
        @mutex.synchronize do
          readmit!
          pool = healthy_nodes
          pool = @nodes if pool.empty?
          pool.uniq(&:account_id).sample(count)
        end
      end

      def increase_backoff(node)
        @mutex.synchronize do
          node.increase_backoff!(now)
          evict(node) if node.dead?(@max_node_attempts)
        end
      end

      def decrease_backoff(node) = @mutex.synchronize { node.decrease_backoff! }

      def healthy_nodes = @mutex.synchronize { @nodes.select { |node| node.healthy?(now) } }

      def close
        @mutex.synchronize do
          @nodes.each { |node| node.close if node.respond_to?(:close) }
          @nodes = []
          @by_account = {}
        end
      end

      private

      def now = Clock.now

      # Readmission is lazy: a node rejoins simply by its readmit time passing,
      # which #healthy? already reports. There is nothing to do here unless the
      # node was evicted, so this exists as the documented hook the reference
      # implementation has and as the place a timer would go if one were ever
      # wanted.
      def readmit!; end

      def evict(node)
        @nodes.delete(node)
        @by_account[node.account_id]&.delete(node)
        @by_account.delete(node.account_id) if @by_account[node.account_id]&.empty?
        node.close if node.respond_to?(:close)
      end
    end
  end
end
