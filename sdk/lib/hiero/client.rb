# frozen_string_literal: true

module Hiero
  # Configuration, and ownership of the connections to a network.
  #
  # One Client per process, shared. It is thread-safe; the requests you build with
  # it are not. See {file:README.md} for the full contract.
  #
  # There is one concrete Client, unlike the JavaScript SDK's three. That SDK
  # needs a subclass per runtime to supply a channel implementation for Node,
  # browsers and React Native; Ruby has one runtime and speaks native gRPC.
  class Client
    # Durations here are seconds, as everywhere in this SDK. The JavaScript SDK
    # uses milliseconds; mixing the two silently turns a 2 minute budget into 2
    # minutes of milliseconds, so the unit is uniform rather than convenient.
    DEFAULTS = {
      max_attempts: 10,
      min_backoff: 0.25,
      max_backoff: 8.0,
      request_timeout: 120.0,
      grpc_deadline: 10.0,
      # Both replaced with real Hbar values below, once Hbar is loaded.
      max_query_payment: nil,
      # A ceiling the payer accepts, not a price. The network charges what the
      # transaction actually costs and rejects it outright if that exceeds this,
      # so it is a guard against a surprise bill rather than a fee to tune.
      default_max_transaction_fee: nil,
      auto_validate_checksums: false
    }.freeze

    # A local network answers instantly or not at all, so exponential waiting buys
    # nothing and a much larger attempt budget costs nothing.
    LOCAL_MAX_ATTEMPTS = 1_000

    attr_reader :network, :ledger_id
    attr_accessor :operator, :max_attempts, :min_backoff, :max_backoff,
                  :request_timeout, :grpc_deadline, :max_query_payment,
                  :default_max_transaction_fee, :auto_validate_checksums, :logger

    def initialize(network:, ledger_id: nil, operator: nil, local: false, **options)
      @network = Network::ManagedNetwork.new
      @network.replace(self.class.normalize_network(network))
      @ledger_id = LedgerId.coerce(ledger_id)
      @operator = operator
      @local = local
      @closed = false
      @mutex = Monitor.new

      settings = DEFAULTS.merge(max_query_payment: Hbar.new(1),
                                default_max_transaction_fee: Hbar.new(2))
      settings = settings.merge(max_attempts: LOCAL_MAX_ATTEMPTS) if local
      settings.merge(options).each { |name, value| public_send(:"#{name}=", value) }
    end

    class << self
      # @param map [Hash{String => Object}] "host:port" => node account id
      def for_network(map, **options) = new(network: map, **options)

      # The local solo / hiero-local-node defaults. Checksums are not validated
      # and the address book is not refreshed: a local network has neither a
      # published ledger id nor an address book worth polling.
      def for_local_node(address: "127.0.0.1:50211", account_id: "0.0.3", **options)
        new(network: { address => account_id }, local: true, **options)
      end

      def for_mainnet(**options)    = new(network: MAINNET_NODES, ledger_id: :mainnet, **options)
      def for_testnet(**options)    = new(network: TESTNET_NODES, ledger_id: :testnet, **options)
      def for_previewnet(**options) = new(network: PREVIEWNET_NODES, ledger_id: :previewnet, **options)

      def for_name(name, **options)
        case name.to_s
        when "mainnet" then for_mainnet(**options)
        when "testnet" then for_testnet(**options)
        when "previewnet" then for_previewnet(**options)
        when "local", "localhost", "local-node" then for_local_node(**options)
        else raise ArgumentError, "unknown network #{name.inspect}"
        end
      end

      # Yields a client and closes it afterwards.
      #
      # Closing matters: a Client owns gRPC connections and, later, background
      # threads, and forgetting to close one keeps a script from exiting. The block
      # form makes that structurally impossible.
      def open(name_or_options = nil, **options)
        client = name_or_options.is_a?(Hash) || name_or_options.nil? ?
                   new(**(name_or_options || {}).merge(options)) :
                   for_name(name_or_options, **options)
        return client unless block_given?

        begin
          yield client
        ensure
          client.close
        end
      end

      def normalize_network(map)
        map.to_h { |address, account_id| [address.to_s, AccountId.coerce(account_id)] }
      end
    end

    # @param account_id [AccountId, String, Integer]
    # @param private_key [PrivateKey]
    def set_operator(account_id, private_key)
      self.operator = Operator.new(account_id: account_id, private_key: private_key)
      self
    end

    # Signs through a callable rather than a local key, so the key can live in an
    # HSM or KMS and never enter this process.
    def set_operator_with(account_id, public_key, &signer)
      self.operator = Operator.new(account_id: account_id, public_key: public_key, &signer)
      self
    end

    def operator_account_id = @operator&.account_id

    def local? = @local
    def closed? = @mutex.synchronize { @closed }

    # @param map [Hash{String => Object}] replaces the node pool wholesale
    def network=(map)
      @network.replace(self.class.normalize_network(map))
    end

    # Not an endless definition: Ruby does not allow those for setters.
    def ledger_id=(value)
      @ledger_id = LedgerId.coerce(value)
    end

    def close
      @mutex.synchronize do
        return self if @closed

        @network.close
        @closed = true
        self
      end
    end

    def ensure_open!
      raise ClientClosedError, "this Client has been closed" if closed?
    end

    def inspect
      "#<#{self.class} #{@network.account_ids.length} nodes" \
        "#{@ledger_id ? " #{@ledger_id}" : ''}#{@operator ? " operator=#{@operator.account_id}" : ''}>"
    end

    # Address books are hard-coded rather than discovered, so a client can reach a
    # public network before it can ask anything about it. They are refreshed from
    # the network itself once that is implemented.
    MAINNET_NODES = {
      "35.237.200.180:50211" => "0.0.3", "35.186.191.247:50211" => "0.0.4",
      "35.192.2.25:50211" => "0.0.5", "35.199.161.108:50211" => "0.0.6",
      "35.203.82.240:50211" => "0.0.7", "35.236.5.219:50211" => "0.0.8",
      "35.197.192.225:50211" => "0.0.9", "35.242.233.154:50211" => "0.0.10",
      "35.240.118.96:50211" => "0.0.11", "35.204.86.32:50211" => "0.0.12"
    }.freeze

    TESTNET_NODES = {
      "0.testnet.hedera.com:50211" => "0.0.3", "1.testnet.hedera.com:50211" => "0.0.4",
      "2.testnet.hedera.com:50211" => "0.0.5", "3.testnet.hedera.com:50211" => "0.0.6"
    }.freeze

    PREVIEWNET_NODES = {
      "0.previewnet.hedera.com:50211" => "0.0.3", "1.previewnet.hedera.com:50211" => "0.0.4",
      "2.previewnet.hedera.com:50211" => "0.0.5", "3.previewnet.hedera.com:50211" => "0.0.6"
    }.freeze
  end
end
