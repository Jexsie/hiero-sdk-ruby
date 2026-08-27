# frozen_string_literal: true

require_relative "lib/hiero/proto/version"

Gem::Specification.new do |spec|
  spec.name     = "hiero-proto"
  spec.version  = Hiero::Proto::VERSION
  spec.authors  = ["Hiero Ruby SDK contributors"]
  spec.license  = "Apache-2.0"

  spec.summary  = "Generated protobuf and gRPC classes for the Hiero API (HAPI)"
  spec.description = <<~DESC
    Protocol Buffer message classes and gRPC service stubs for the Hiero API,
    generated from the .proto definitions published by the Hiero consensus node
    and mirror node. The generated sources are committed and shipped, so
    installing this gem never requires protoc.

    This gem is the transport layer for hiero-sdk. Most applications should
    depend on hiero-sdk instead of using these classes directly.
  DESC

  # Hosted personally while the SDK stabilises; to be transferred to the
  # hiero-ledger organisation once it is ready.
  spec.homepage = "https://github.com/Jexsie/hiero-sdk-ruby"
  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "bug_tracker_uri"   => "#{spec.homepage}/issues",
    "hapi_version"      => Hiero::Proto::HAPI_VERSION,
    "mirror_version"    => Hiero::Proto::MIRROR_VERSION,
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 4.0"

  # The vendored .proto sources ship alongside the generated Ruby: they are small,
  # and they let consumers see exactly which definitions produced these classes.
  # Dir globs resolve against the working directory, not the gemspec, so this has
  # to chdir explicitly -- otherwise `gem build proto/hiero-proto.gemspec` from the
  # repository root silently produces an almost-empty gem.
  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*.rb",
      "hapi/**/*.proto",
      "HAPI_VERSION",
      "MIRROR_VERSION",
      "LICENSE",
      "NOTICE"
    ]
  end
  spec.require_paths = ["lib"]

  # google-protobuf must match the runtime the classes were generated against.
  spec.add_dependency "google-protobuf", ">= 4.30", "< 5.0"
  spec.add_dependency "grpc", ">= 1.60", "< 2.0"
end
