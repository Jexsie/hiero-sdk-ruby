# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "yaml"

require "hiero"

# Specs build protobuf messages directly to stand in for node responses, so the
# generated classes have to be present. Application code gets them by
# constructing a request; a spec asserting on a response has not constructed one.
Hiero.protobuf!

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Integration specs need a running network, so they are opt-in:
  #
  #   bundle exec rake spec:integration
  #   bundle exec rspec --tag integration ...
  #
  # Skipped rather than failed when nothing is listening, so a plain `rspec` is
  # always green on a laptop with no network running.
  config.filter_run_excluding(:integration) unless config.filter.rules[:integration]

  config.before(:each, :integration) do
    Solo.require_or_skip!(self, Solo.reachable?, "no consensus node at #{Solo::ADDRESS}")
  end

  # Specs that need a funded account to pay with.
  config.before(:each, :operator) do
    Solo.require_or_skip!(self, !Solo.operator.nil?,
                          "no operator configured; set HIERO_OPERATOR_ID and HIERO_OPERATOR_KEY")
    Solo.require_or_skip!(self, !Solo.test_operator.nil?, Solo.funding_error.to_s)
  end
end

# A locally running Hiero network. Defaults match hiero-solo; override through the
# environment for hiero-local-node or anything else.
module Solo
  ADDRESS      = ENV.fetch("HIERO_NODE_ADDRESS", "localhost:35211")
  NODE_ACCOUNT = ENV.fetch("HIERO_NODE_ACCOUNT", "0.0.3")
  MIRROR_REST  = ENV.fetch("HIERO_MIRROR_REST", "http://localhost:38081")

  # The treasury, which exists on every network and always holds a balance.
  TREASURY = "0.0.2"

  # In CI a missing network is a failure, not a skip. A suite that quietly skips
  # everything reports green, which is worse than useless -- it is the shape of
  # bug where integration coverage silently stops running for months.
  REQUIRED = ENV["HIERO_REQUIRE_NETWORK"] == "1"

  def self.network = { ADDRESS => NODE_ACCOUNT }

  # @return [Hiero::Operator, nil] a funded account to pay with, if configured
  def self.operator
    return @operator if defined?(@operator)

    account_id = ENV.fetch("HIERO_OPERATOR_ID", nil)
    key = ENV.fetch("HIERO_OPERATOR_KEY", nil)

    @operator =
      if account_id && key
        Hiero::Operator.new(account_id: account_id, private_key: Hiero::PrivateKey.from_string(key))
      end
  end

  def self.require_or_skip!(example, satisfied, message)
    return if satisfied
    raise "#{message} (HIERO_REQUIRE_NETWORK is set, so this is a failure rather than a skip)" if REQUIRED

    example.skip(message)
  end

  # Whether a node will actually answer.
  #
  # Deliberately a real query rather than a TCP connect. A solo network fronts
  # its consensus node with HAProxy, which keeps listening after the node behind
  # it dies -- so the socket opens, every request then times out, and with a
  # local network's large attempt budget each example burns the entire
  # request_timeout before failing. A suite that takes twenty minutes to report a
  # dead network is indistinguishable from one that has hung, which is exactly
  # what happened before this was changed.
  def self.reachable?
    return @reachable unless @reachable.nil?

    client = Hiero::Client.for_network(network, local: true, max_attempts: 1, grpc_deadline: 3.0)
    begin
      Hiero::AccountBalanceQuery.new(account_id: TREASURY).execute(client, timeout: 5)
      @reachable = true
    rescue StandardError
      @reachable = false
    ensure
      client.close
    end
  end

  # A fresh account, created and funded once per run, that the specs pay with.
  #
  # Two reasons not to spend the configured operator directly. Transactions cost
  # money, so a suite that pays from a fixed account drains it and starts failing
  # after enough runs -- which it did, with different examples failing each time
  # depending on what was left. And the configured operator may be the treasury,
  # which pays no fees at all, so any assertion about a payer being charged is
  # unobservable through it.
  #
  # An ordinary account created per run is repeatable and behaves like a real one.
  # Enough for a run several times over. Kept modest so a funder with a small
  # balance can still stand one up.
  TEST_ACCOUNT_BALANCE = 25

  # Why the test account could not be created, if it could not be.
  def self.funding_error = (test_operator; @funding_error)

  def self.test_operator
    return @test_operator if defined?(@test_operator)

    @funding_error = nil
    @test_operator = nil
    return nil if operator.nil?

    key = Hiero::PrivateKey.generate_ed25519
    funder = Hiero::Client.for_network(network, local: true, operator: operator, request_timeout: 30.0)
    begin
      receipt = Hiero::AccountCreateTransaction
                .new(key: key.public_key, initial_balance: Hiero::Hbar.new(TEST_ACCOUNT_BALANCE))
                .set_account_memo("hiero-sdk-ruby integration run")
                .execute(funder)
                .receipt(funder)
      @test_operator = Hiero::Operator.new(account_id: receipt.account_id, private_key: key)
    rescue StandardError => e
      # Reported once, with the reason. Left to fail lazily this surfaces as every
      # example failing for a different-looking reason.
      @funding_error = "#{operator.account_id} could not fund a #{TEST_ACCOUNT_BALANCE} hbar " \
                       "test account: #{e.class} #{e.message.lines.first.to_s.strip}"
      nil
    ensure
      funder.close
    end
  end

  # A short budget by default. The SDK's own two-minute ceiling is right for
  # production, where a slow answer beats no answer; in a spec it only means a
  # failure takes two minutes to arrive.
  def self.client(**options)
    Hiero::Client.for_network(network, local: true, operator: test_operator,
                              request_timeout: 15.0, max_attempts: 10, **options)
  end

  # A client paying with the operator the environment configured, for the specs
  # that are about that handoff rather than about spending.
  def self.configured_client(**options)
    Hiero::Client.for_network(network, local: true, operator: operator,
                              request_timeout: 15.0, max_attempts: 10, **options)
  end
end

# Test vectors taken from the JavaScript SDK's cryptography suite
# (packages/cryptography/test/unit). They are shared across the Hiero SDKs, so
# agreeing with them is what "compatible" actually means here -- an SDK that
# signs self-consistently but differently from its siblings is broken.
module Vectors
  # Primitive-level vectors, exercised by the Hiero::Crypto specs.
  ED25519_SEED = "db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10"
  ED25519_PUBLIC = "e0c8ec2758a5879ffac226a13c0c516b799e72e35141a0dd828f94d37988a4b7"
  ED25519_SEED_DER =
    "302e020100300506032b657004220420db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10"

  ECDSA_PRIVATE = "8776c6b831a1b61ac10dac0304a2843de4716f54b1919bb91a2685d0fe3f3048"

  # sign(keccak256("hello world"))
  ECDSA_MESSAGE = "hello world"
  ECDSA_SIGNATURE =
    "f3a13a555f1f8cd6532716b8f388bd4e9d8ed0b252743e923114c0c6cbfe414c" \
    "086e3717a6502c3edff6130d34df252fb94b6f662d0cd27e2110903320563851"

  # sign(keccak256(<a real serialized transaction body>))
  ECDSA_BODY_BYTES =
    "0a0e0a0408011001120608001000180412060800100018031880c2d72f2202087832007" \
    "21a0a180a0a0a0608001000180410130a0a0a060800100018051014"
  ECDSA_BODY_SIGNATURE =
    "63201532040178a60e2738bdaaa00d628004b15d109162fa42e066fcb6720190" \
    "438473bbf155fd7ff6bfb2a94141157f1e1a080aa84473d7f4c68f8025275a0a"

  # Key-class vectors: a different, matched set where each private key derives the
  # public key beside it. Deliberately distinct constants from the primitive
  # vectors above -- reusing the names silently redefines them and the mismatch
  # only shows up as a confusing failure elsewhere.
  ED25519_PRIVATE_RAW = "ee417dd399722ef8920b2c8ec047cf0c51d6c7d3413e9a660ca28205a5f249cd"
  ED25519_PRIVATE_DER =
    "302e020100300506032b657004220420ee417dd399722ef8920b2c8ec047cf0c51d6c7d3413e9a660ca28205a5f249cd"
  ED25519_PUBLIC_RAW = "6efd7f7de3ce5caadc830818a8a0bbab7da2c2cdfa6778e9b351c8f519801ae2"
  ED25519_PUBLIC_DER =
    "302a300506032b65700321006efd7f7de3ce5caadc830818a8a0bbab7da2c2cdfa6778e9b351c8f519801ae2"

  ECDSA_PRIVATE_RAW = "4c6c731ed7123a213eaf37dd72f19220b7005d243cfd52d080708ec5fe032b36"
  ECDSA_PRIVATE_DER =
    "3030020100300706052b8104000a042204204c6c731ed7123a213eaf37dd72f19220b7005d243cfd52d080708ec5fe032b36"
  ECDSA_PUBLIC_RAW = "038592559824a68150512e5c23736885208382859ac5aad7a73adc48226fe122b5"
  ECDSA_PUBLIC_DER =
    "302d300706052b8104000a032200038592559824a68150512e5c23736885208382859ac5aad7a73adc48226fe122b5"

  # The fully qualified X.509 spelling of an ECDSA public key. Hiero accepts it on
  # input but never emits it.
  ECDSA_PUBLIC_DER_X509 =
    "3036301006072a8648ce3d020106052b8104000a032200038592559824a68150512e5c23736885208382859ac5aad7a73adc48226fe122b5"

  # An Ethereum key and its address, from the Truffle test suite.
  EVM_PUBLIC_KEY = "03af80b90d25145da28c583359beb47b21796b2fe1a23c1511e443e7a64dfdb27d"
  EVM_ADDRESS    = "627306090abab3a6e1400e9345bc60c78a8bef57"

  # BIP-39 mnemonics. The first two are official BIP-39 test vectors; the last two
  # are Hiero-path vectors from the JavaScript SDK's suite.
  BIP39_ZERO_ENTROPY = "00000000000000000000000000000000"
  BIP39_ZERO_WORDS = "abandon abandon abandon abandon abandon abandon " \
                     "abandon abandon abandon abandon abandon about"
  BIP39_ZERO_SEED_TREZOR =
    "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141" \
    "630c7a3c4ab7c81b2f001698e7463b04"

  # Generated by hiero-keygen-java. m/44'/3030'/0'/0' over SLIP-10 Ed25519.
  HIERO_ED25519_MNEMONIC =
    "inmate flip alley wear offer often piece magnet surge toddler submit right " \
    "radio absent pear floor belt raven price stove replace reduce plate home"
  HIERO_ED25519_DERIVED = "853f15aecd22706b105da1d709b4ac05b4906170c2b9c7495dff9af49e1391da"

  # m/44'/60'/0'/0 over BIP-32 secp256k1, from a widely used Ethereum test gist.
  ETH_MNEMONIC = "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat"
  ETH_ROOT = "c4d1decb7eb3679f1adafa9795ee019f2480626554b80f058f063dfb84acb227"
  ETH_CHILDREN = %w[
    c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3
    ae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f
    0dbbe8e4ae425a6d2687f1a7e3ba17bc98c673636790f1b8ad91193c05875ef1
    c88b703fb08cbea894b6aeff5a544fb92e78a18e19814cd85da83b71f772aa6c
  ].freeze

  # The canonical empty-input Keccak digest. Distinguishes Keccak from SHA3-256,
  # which pads differently and returns something else entirely.
  KECCAK_EMPTY = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

  def self.bin(hex) = [hex].pack("H*")
end
