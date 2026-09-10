# frozen_string_literal: true

RSpec.describe Hiero::Channel do
  subject(:channel) { described_class.new("localhost:50211") }

  after { channel.close }

  it "exposes all ten HAPI services" do
    expect(described_class::SERVICES.keys).to contain_exactly(
      :crypto, :smart_contract, :file, :consensus, :token,
      :schedule, :freeze, :network, :util, :address_book
    )
    expect(described_class::SERVICES.keys.map { |s| channel.stub(s) }).to all(be_a(GRPC::ClientStub))
  end

  it "gives each service a reader" do
    expect(channel.crypto).to be_a(Proto::CryptoService::Stub)
    expect(channel.consensus).to be_a(Proto::ConsensusService::Stub)
  end

  it "memoises each stub" do
    expect(channel.crypto).to be(channel.crypto)
  end

  it "puts every service on ONE connection" do
    # Without channel_override the grpc gem opens a connection per stub, which
    # would be ten per node. This is the assertion that keeps that from regressing.
    connection = lambda do |stub|
      stub.instance_variables
          .map { |v| stub.instance_variable_get(v) }
          .find { |o| o.is_a?(GRPC::Core::Channel) }
    end

    expect(connection.(channel.crypto)).to be(connection.(channel.token))
  end

  it "rejects an unknown service" do
    expect { channel.stub(:nonsense) }.to raise_error(ArgumentError, /unknown service/)
  end

  it "can be closed more than once" do
    expect { 2.times { channel.close } }.not_to raise_error
  end

  it "does not connect on construction" do
    # gRPC connects lazily, so building a Channel for an unreachable address must
    # not raise -- the network is allowed to contain nodes that are currently down.
    expect { described_class.new("192.0.2.1:50211").close }.not_to raise_error
  end
end
