# frozen_string_literal: true

# Against a real consensus node. Skipped when nothing is listening, so a plain
# `rspec` stays green without a network; run with:
#
#   bundle exec rake spec:integration
#
# What these add over the unit specs is everything the unit specs have to fake:
# the wire format a node actually accepts, the statuses it actually returns, and
# whether a deadline is honoured by gRPC rather than by a mock.
RSpec.describe "AccountBalanceQuery against a live network", :integration do
  let(:client) { Solo.client }

  after { client.close }

  it "reads the treasury balance" do
    balance = Hiero::AccountBalanceQuery.new(account_id: Solo::TREASURY).execute(client)

    expect(balance.hbars).to be_a(Hiero::Hbar)
    expect(balance.hbars).to be_positive
    expect(balance.account_id).to eq(Hiero::AccountId.from_string(Solo::TREASURY))
  end

  it "reads the node's own account" do
    balance = Hiero::AccountBalanceQuery.new(account_id: Solo::NODE_ACCOUNT).execute(client)

    expect(balance.hbars.to_tinybars).to be >= 0
  end

  it "reports an unknown account as a precheck failure" do
    # The node rejects this before consensus, so nothing was charged. That
    # distinction is the whole reason PrecheckStatusError is its own class.
    query = Hiero::AccountBalanceQuery.new(account_id: "0.0.999999999")

    expect { query.execute(client) }.to raise_error(Hiero::PrecheckStatusError) do |error|
      expect(error.status).to eq(Hiero::Status::INVALID_ACCOUNT_ID)
      expect(error.node_account_id).to eq(Hiero::AccountId.from_string(Solo::NODE_ACCOUNT))
    end
  end

  it "needs no operator, being a free query" do
    # Built without one deliberately, rather than relying on the shared client
    # happening not to have an operator configured.
    anonymous = Hiero::Client.for_network(Solo.network, local: true)

    expect(anonymous.operator).to be_nil
    expect { Hiero::AccountBalanceQuery.new(account_id: Solo::TREASURY).execute(anonymous) }
      .not_to raise_error
  ensure
    anonymous&.close
  end

  it "gives up on an unreachable node instead of hanging" do
    unreachable = Hiero::Client.for_network({ "127.0.0.1:1" => "0.0.3" },
                                            local: true, max_attempts: 3, min_backoff: 0.01)

    expect { Hiero::AccountBalanceQuery.new(account_id: "0.0.2").execute(unreachable, timeout: 5) }
      .to raise_error(Hiero::MaxAttemptsError) { |e| expect(e.cause).to be_a(GRPC::Unavailable) }
  ensure
    unreachable&.close
  end

  it "honours the overall timeout" do
    unreachable = Hiero::Client.for_network({ "127.0.0.1:1" => "0.0.3" },
                                            local: true, max_attempts: 10_000, min_backoff: 0.01)
    started = Hiero::Clock.now

    expect { Hiero::AccountBalanceQuery.new(account_id: "0.0.2").execute(unreachable, timeout: 0.5) }
      .to raise_error(Hiero::MaxAttemptsError)
    expect(Hiero::Clock.now - started).to be < 3.0
  ensure
    unreachable&.close
  end
end
