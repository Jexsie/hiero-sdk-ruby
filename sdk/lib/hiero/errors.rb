# frozen_string_literal: true

module Hiero
  # Base class for everything this SDK raises. `rescue Hiero::Error` catches the
  # SDK and nothing else.
  class Error < StandardError; end

  # A key could not be parsed, is the wrong length, is not a valid point on the
  # curve, or was asked to do something its algorithm does not support.
  class BadKeyError < Error; end
end
