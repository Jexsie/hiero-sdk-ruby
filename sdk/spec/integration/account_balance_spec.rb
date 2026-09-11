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

# The paid path, which the free queries never exercise: the node quotes a price,
# the client signs a transfer for it, and only then does the node answer.
RSpec.describe "AccountInfoQuery against a live network", :integration, :operator do
  let(:client) { Solo.client }

  after { client.close }

  it "quotes a price before answering" do
    cost = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY).cost(client)

    expect(cost).to be_a(Hiero::Hbar)
    expect(cost).to be_positive
  end

  it "pays the quoted price and returns the account" do
    info = Hiero::AccountInfoQuery.new(account_id: client.operator_account_id).execute(client)

    expect(info.account_id).to eq(client.operator_account_id)
    expect(info.balance).to be_positive
    expect(info.key).to eq(client.operator.public_key)
  end

  describe "the payment is real" do
    # Not asserted by watching the payer's balance. A single-node network does not
    # collect the query fee -- the node would be paying itself -- so the balance
    # does not move even though the payment is required and checked. What proves
    # the payment works is that the node refuses a bad one.
    it "refuses a query that pays nothing" do
      query = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY)
      query.query_payment = Hiero::Hbar::ZERO

      expect { query.execute(client) }.to raise_error(Hiero::PrecheckStatusError) do |error|
        expect(error.status).to eq(Hiero::Status::INSUFFICIENT_TX_FEE)
      end
    end

    it "refuses a payment signed by the wrong key" do
      impostor = Hiero::PrivateKey.generate_ed25519
      wrong = Hiero::Client.for_network(Solo.network, local: true, request_timeout: 15.0)
      wrong.set_operator_with(client.operator_account_id, impostor.public_key) { |b| impostor.sign(b) }

      query = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY)
      query.query_payment = Hiero::Hbar.from_tinybars(100_000)

      expect { query.execute(wrong) }.to raise_error(Hiero::PrecheckStatusError) do |error|
        expect(error.status).to eq(Hiero::Status::INVALID_SIGNATURE)
      end
    ensure
      wrong&.close
    end

    it "accepts a payment at the quoted price" do
      query = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY)
      query.query_payment = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY).cost(client)

      expect(query.execute(client).account_id).to eq(Hiero::AccountId.from_string(Solo::TREASURY))
    end
  end

  it "accepts a price set in advance, skipping the enquiry" do
    # Modest but comfortably above the real price. The node checks the payer can
    # afford the payment even though a single-node network does not collect it,
    # so an extravagant figure here fails on balance rather than on anything the
    # spec is about.
    query = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY)
    query.query_payment = Hiero::Hbar.from_tinybars(1_000_000)

    # The whole point of setting a price is that the cost enquiry is skipped, so
    # that is asserted rather than assumed.
    expect(query).not_to receive(:cost)
    expect(query.execute(client).account_id).to eq(Hiero::AccountId.from_string(Solo::TREASURY))
  end

  it "refuses to pay more than the ceiling" do
    query = Hiero::AccountInfoQuery.new(account_id: Solo::TREASURY)
    query.max_query_payment = Hiero::Hbar.from_tinybars(1)

    expect { query.execute(client) }.to raise_error(Hiero::MaxQueryPaymentExceededError)
  end
end
