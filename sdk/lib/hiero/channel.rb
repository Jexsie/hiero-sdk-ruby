# frozen_string_literal: true

module Hiero
  # The gRPC transport to one node.
  #
  # A lazy façade over the ten HAPI services. All of them share a single
  # underlying connection: without `channel_override:` the gRPC gem opens a
  # separate TCP connection per stub, which would be ten per node.
  #
  # Service classes are resolved by name rather than referenced directly, so that
  # defining this class does not force hiero-proto -- and therefore gRPC -- to
  # load. See {Hiero.protobuf!}.
  class Channel
    SERVICES = {
      crypto: "CryptoService",
      smart_contract: "SmartContractService",
      file: "FileService",
      consensus: "ConsensusService",
      token: "TokenService",
      schedule: "ScheduleService",
      freeze: "FreezeService",
      network: "NetworkService",
      util: "UtilService",
      address_book: "AddressBookService"
    }.freeze

    # Keepalives matter here. Consensus nodes have been observed to hold a
    # connection open and answer neither way, and a dead connection that is never
    # noticed turns every request into a deadline timeout.
    ARGS = {
      "grpc.keepalive_time_ms" => 100_000,
      "grpc.keepalive_timeout_ms" => 10_000,
      "grpc.keepalive_permit_without_calls" => 1
    }.freeze

    attr_reader :address

    # @param address [String] "host:port"
    # @param credentials [Object, nil] gRPC channel credentials, or nil for plaintext
    def initialize(address, credentials: nil)
      Hiero.protobuf!

      @address = address
      @credentials = credentials || :this_channel_is_insecure
      @stubs = {}
      @mutex = Monitor.new
    end

    SERVICES.each_key do |service|
      define_method(service) { stub(service) }
    end

    # @return [Object] the gRPC stub for one HAPI service, memoised
    def stub(service)
      name = SERVICES.fetch(service) { raise ArgumentError, "unknown service #{service.inspect}" }

      @mutex.synchronize do
        # ::Proto, not Proto. Inside module Hiero the latter resolves to
        # Hiero::Proto -- hiero-proto's own version module -- rather than to the
        # top-level namespace the generated HAPI classes live in.
        @stubs[service] ||= ::Proto.const_get(name)::Stub.new(
          @address, @credentials, channel_override: grpc_channel
        )
      end
    end

    def close
      @mutex.synchronize do
        @stubs.clear
        @grpc_channel&.close
        @grpc_channel = nil
      end
    end

    def inspect = "#<#{self.class} #{@address}>"

    private

    def grpc_channel
      @grpc_channel ||= GRPC::Core::Channel.new(
        @address,
        ARGS.merge("grpc.primary_user_agent" => "hiero-sdk-ruby/#{Hiero::VERSION}"),
        @credentials
      )
    end
  end
end
