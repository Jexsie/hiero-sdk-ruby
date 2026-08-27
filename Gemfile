# frozen_string_literal: true

source "https://rubygems.org"

gemspec path: "proto", name: "hiero-proto"

group :development do
  # Bundles protoc and the Ruby gRPC plugin used by bin/generate_protos. Pinned,
  # because the generated output is committed and a different protoc produces a
  # spurious diff -- see the regeneration check in .github/workflows/ci.yml.
  gem "grpc-tools", "1.83.0"

  gem "rake",  "~> 13.0"
  gem "rspec", "~> 3.13"
end
