# frozen_string_literal: true

require_relative "lib/hiero/version"

Gem::Specification.new do |spec|
  spec.name    = "hiero-sdk"
  spec.version = Hiero::VERSION
  spec.authors = ["Hiero Ruby SDK contributors"]
  spec.license = "Apache-2.0"

  spec.summary = "A Ruby SDK for Hiero"
  spec.description = <<~DESC
    A Ruby toolkit for creating, updating, and interacting with accounts, tokens,
    files, topics, and smart contracts on a Hiero network.
  DESC

  # Hosted personally while the SDK stabilises; to be transferred to the
  # hiero-ledger organisation once it is ready.
  spec.homepage = "https://github.com/Jexsie/hiero-sdk-ruby"
  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "bug_tracker_uri"       => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "LICENSE", "NOTICE"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "hiero-proto", ">= 0.1.0"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Deliberately no cryptography dependencies. Ed25519, ECDSA secp256k1 and
  # keccak256 are all implemented on Ruby's stdlib OpenSSL -- see
  # docs/adr/0001-cryptography-backends.md. Installing digest-keccak is optional
  # and makes hashing roughly 400x faster; nothing breaks without it.
end
