# frozen_string_literal: true

require "zeitwerk"

require_relative "hiero/version"

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
  @loader = Zeitwerk::Loader.for_gem
  @loader.ignore("#{__dir__}/hiero/version.rb")
  @loader.setup
  @loader.eager_load
end
