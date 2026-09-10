# frozen_string_literal: true

RSpec.describe Hiero::Executable do
  # A subclass whose every hook is scripted, so the loop can be driven through
  # each branch without a network. The gRPC wiring is covered separately, against
  # a real server; what is under test here is attempts, rotation and deadlines.
  class ScriptedRequest < Hiero::Executable
    attr_reader :attempts, :nodes_called, :deadlines

    # @param outcomes [Array] per attempt: :ok, :retry, :error, or an Exception
    def initialize(outcomes)
      super()
      @outcomes = outcomes.dup
      @attempts = 0
      @nodes_called = []
      @deadlines = []
    end

    def make_request = { attempt: @attempts }

    def call(channel, _request, deadline:)
      @attempts += 1
      @nodes_called << channel.address
      @deadlines << deadline

      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      outcome
    end

    def execution_state(_request, response)
      state = response == :ok ? :finished : response
      [Hiero::Status::OK, state]
    end

    def map_response(response, node_account_id, _request) = [response, node_account_id]
    def map_status_error(_request, _response, node_account_id) = Hiero::Error.new("failed on #{node_account_id}")
  end

  def client(**options)
    Hiero::Client.for_network(
      { "a:1" => "0.0.3", "b:2" => "0.0.4", "c:3" => "0.0.5" },
      min_backoff: 0.001, max_backoff: 0.002, **options
    )
  end

  it "returns the mapped response when the first attempt finishes" do
    request = ScriptedRequest.new([:ok])

    result, node = request.execute(client)

    expect(result).to eq(:ok)
    expect(node).to be_a(Hiero::AccountId)
    expect(request.attempts).to eq(1)
  end

  it "raises the mapped error without retrying" do
    request = ScriptedRequest.new([:error])

    expect { request.execute(client) }.to raise_error(Hiero::Error, /failed on/)
    expect(request.attempts).to eq(1)
  end

  describe "retrying" do
    it "retries a retryable status and succeeds later" do
      request = ScriptedRequest.new(%i[retry retry ok])

      expect(request.execute(client).first).to eq(:ok)
      expect(request.attempts).to eq(3)
    end

    it "moves to a different node on each attempt" do
      request = ScriptedRequest.new(%i[retry retry ok])
      request.execute(client)

      expect(request.nodes_called.uniq.length).to eq(3)
    end

    it "gives up after max_attempts" do
      request = ScriptedRequest.new([:retry] * 10)

      expect { request.execute(client(max_attempts: 4)) }
        .to raise_error(Hiero::MaxAttemptsError, /exhausted 4 attempts/)
      expect(request.attempts).to eq(4)
    end

    it "reports the last underlying failure as the cause" do
      # Ruby only sets #cause automatically inside a rescue, and the last failure
      # here happened several attempts earlier -- so it is threaded through
      # explicitly rather than buried in a message.
      request = ScriptedRequest.new([:retry] * 3)

      begin
        request.execute(client(max_attempts: 2))
      rescue Hiero::MaxAttemptsError => e
        expect(e.cause).to be_a(Hiero::Error)
        expect(e.attempts).to eq(2)
      end
    end
  end

  describe "transport errors" do
    it "retries a retryable gRPC error on another node" do
      request = ScriptedRequest.new([GRPC::Unavailable.new("node down"), :ok])

      expect(request.execute(client).first).to eq(:ok)
      expect(request.nodes_called.uniq.length).to eq(2)
    end

    it "marks the failing node unhealthy so it is skipped" do
      c = client
      request = ScriptedRequest.new([GRPC::Unavailable.new("down"), :ok])
      request.execute(c)

      expect(c.network.healthy_nodes.length).to eq(2)
    end

    it "restores a node's health after a success" do
      c = client
      ScriptedRequest.new([:ok]).execute(c)

      expect(c.network.healthy_nodes.length).to eq(3)
    end

    it "does not retry an error that is not retryable" do
      request = ScriptedRequest.new([GRPC::InvalidArgument.new("malformed")])

      expect { request.execute(client) }.to raise_error(GRPC::InvalidArgument)
      expect(request.attempts).to eq(1)
    end
  end

  describe "deadlines" do
    it "passes gRPC a deadline rather than racing a timer" do
      # gRPC enforces this in its C core, which covers the case a consensus node
      # holds a connection open and answers neither way.
      request = ScriptedRequest.new([:ok])
      request.execute(client(grpc_deadline: 5.0))

      expect(request.deadlines.first).to be_within(1.0).of(Time.now + 5.0)
    end

    it "never lets one call overshoot the overall budget" do
      request = ScriptedRequest.new([:ok])
      request.execute(client(grpc_deadline: 30.0), timeout: 2.0)

      expect(request.deadlines.first).to be <= Time.now + 2.1
    end

    it "gives up when the overall budget runs out mid-retry" do
      request = ScriptedRequest.new([:retry] * 100)

      expect { request.execute(client(max_attempts: 100), timeout: 0.05) }
        .to raise_error(Hiero::MaxAttemptsError, /timed out/)
    end
  end

  describe "configuration" do
    it "inherits unset knobs from the client" do
      request = ScriptedRequest.new([:ok])
      request.execute(client(max_attempts: 7))

      expect(request.max_attempts).to eq(7)
    end

    it "lets a request override one knob without disturbing the client" do
      c = client(max_attempts: 7)
      request = ScriptedRequest.new([:retry] * 5)
      request.max_attempts = 2

      expect { request.execute(c) }.to raise_error(Hiero::MaxAttemptsError, /2 attempts/)
      expect(c.max_attempts).to eq(7)
    end

    it "sends only to the nodes it was pinned to" do
      request = ScriptedRequest.new(%i[retry retry ok])
      request.node_account_ids = ["0.0.4"]
      request.execute(client)

      expect(request.nodes_called.uniq).to eq(["b:2"])
    end

    it "skips a pinned node the client does not know about" do
      request = ScriptedRequest.new([:ok])
      request.node_account_ids = ["0.0.99", "0.0.3"]

      expect(request.execute(client).first).to eq(:ok)
    end
  end

  it "refuses to run against a closed client" do
    c = client
    c.close

    expect { ScriptedRequest.new([:ok]).execute(c) }.to raise_error(Hiero::ClientClosedError)
  end

  it "refuses to run with no nodes" do
    expect { ScriptedRequest.new([:ok]).execute(Hiero::Client.for_network({})) }
      .to raise_error(Hiero::Error, /no nodes/)
  end

  describe "the abstract contract" do
    it "names the missing hook" do
      bare = Class.new(Hiero::Executable).new

      expect { bare.make_request }.to raise_error(NotImplementedError, /make_request/)
    end
  end
end
