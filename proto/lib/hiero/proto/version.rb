# frozen_string_literal: true

module Hiero
  module Proto
    # The gem version tracks the HAPI release these classes were generated from,
    # so `hiero-proto 0.76.1` unambiguously means "the Hiero API as of v0.76.1".
    # A regeneration against the same HAPI tag takes a fourth segment: 0.76.1.1.
    VERSION = "0.76.1"

    # The upstream tags the vendored .proto sources were taken from. Kept in sync
    # with proto/HAPI_VERSION and proto/MIRROR_VERSION by bin/generate_protos.
    HAPI_VERSION   = "v0.76.1"
    MIRROR_VERSION = "v0.161.3"
  end
end
