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
end

# Optional at runtime: makes keccak256 roughly 400x faster, and the SDK works
# without it. Its own group so CI can exclude just this one gem and prove the
# pure-Ruby fallback still passes the whole suite:
#
#   BUNDLE_WITHOUT=native_crypto bundle install
#
# Excluding it by installing a smaller set of gems by hand does not work -- the
# suite also needs grpc and hiero-proto, and leaving those out tests the wrong
# absence.
group :native_crypto do
  gem "digest-keccak", "~> 0.0"
end
