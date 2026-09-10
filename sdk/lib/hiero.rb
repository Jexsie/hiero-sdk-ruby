# frozen_string_literal: true

require "monitor"
require "zeitwerk"

require_relative "hiero/version"
require_relative "hiero/errors"

# A Ruby SDK for Hiero.
module Hiero
  class << self
    attr_reader :loader
  end

  # Zeitwerk resolves the constant cycles that force the JavaScript SDK to keep a
  # registry of conversion functions -- AccountId needs PublicKey, PublicKey needs
  # Key, KeyList needs ContractId, ContractId needs AccountId -- so there is no
  # equivalent of its Cache module here.
  #
  # Eager loading is not optional. Transaction.from_bytes dispatches through a
  # registry that each concrete transaction populates as it loads, and it may be
  # the first thing an application calls. Left to autoload lazily, that registry
  # would still be empty.
  # hiero-proto pulls in gRPC, a large native extension that the offline half of
  # this SDK -- keys, mnemonics, identifiers, value types -- has no use for. It is
  # loaded on first use by the transport layer instead of at require time, so
  # wallet and address tooling that never opens a socket does not pay for it.
  def self.protobuf!
    @protobuf ||= begin
      require "hiero/proto"
      true
    end
  end

  @loader = Zeitwerk::Loader.for_gem
  # Both define several constants each, which is the one thing Zeitwerk's
  # file-per-constant rule cannot express, so they are required outright above.
  @loader.ignore("#{__dir__}/hiero/version.rb")
  @loader.ignore("#{__dir__}/hiero/errors.rb")
  @loader.setup
  @loader.eager_load
end
