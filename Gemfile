# frozen_string_literal: true

source "https://rubygems.org"

gemspec path: "proto", name: "hiero-proto"
gemspec path: "sdk",   name: "hiero-sdk"

group :development do
  # Bundles protoc and the Ruby gRPC plugin used by bin/generate_protos. Pinned,
  # because the generated output is committed and a different protoc produces a
  # spurious diff -- see the regeneration check in .github/workflows/ci.yml.
  gem "grpc-tools", "1.83.0"

  gem "rake",  "~> 13.0"
  gem "rspec", "~> 3.13"

  # Optional at runtime: makes keccak256 roughly 400x faster. Installed here so
  # CI exercises the native path as well as the pure-Ruby default.
  gem "digest-keccak", "~> 0.0"
end
