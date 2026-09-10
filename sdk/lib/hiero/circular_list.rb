# frozen_string_literal: true

module Hiero
  # A cursor over a fixed list that wraps around.
  #
  # Requests hold two of these: the nodes an attempt may go to, and -- for chunked
  # transactions -- the transaction ids. The request index is derived from both
  # positions, which is why the cursor is a type rather than a bare integer.
  #
  # A list can be locked once a request has committed to it. A transaction signed
  # for a particular set of nodes cannot be sent anywhere else, so changing the
  # list afterwards would invalidate every signature already collected.
  class CircularList
    include Enumerable

    attr_reader :index

    def initialize(items = [])
      @items = Array(items).dup
      @index = 0
      @locked = false
    end

    def each(&) = @items.each(&)
    def length = @items.length
    alias size length
    def empty? = @items.empty?
    def to_a = @items.dup

    def current = @items[@index]

    def advance
      @index = (@index + 1) % @items.length unless @items.empty?
      current
    end

    def items=(items)
      raise Error, "this list is locked and cannot be replaced" if @locked

      @items = Array(items).dup
      @index = 0
      @items
    end

    def lock! = (@locked = true; self)
    def locked? = @locked
  end
end
