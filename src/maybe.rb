# frozen_string_literal: true

module May
  # Classes extending May::Abstract are abstract classes only that should not
  # be instantiated.
  module Abstract
    # @param klass [Class]
    # @return [NilClass]
    def self.extended(klass)
      klass.define_singleton_method(:new) do |*args, &block|
        if equal?(klass)
          raise NotImplementedError, "#{self} cannot be instantiated"
        else
          super(*args, &block)
        end
      end
    end

    # Declare some methods as required in sub-classes
    # @param methods [Array<Symbol>]
    # @return [NilClass]
    def abstract(*methods)
      methods.each do |method|
        define_method(method) do |*|
          raise NotImplementedError, "#{self.class}##{method} must be defined"
        end
      end
    end

    private :abstract
  end

  class MayError < StandardError; end
  class MustReturnMayBeError < MayError; end
  class UnexpectedNilError < MayError; end
  class ValueMustBeHashError < MayError; end

  # @param value [any]
  # @return [May::Some]
  def self.some(value)
    Some.new(value)
  end

  # @return [May::None]
  def self.none
    None.new
  end
end

class May::Be
  extend May::Abstract
  abstract :and_then,
           :map,
           :or_else,
           :get_or_else,
           :get_or_else_value,
           :assign,
           :effect,
           :or_effect
end

class May::Some < May::Be
  # @param value [any]
  def initialize(value)
    @value = value
  end

  # @return [May::Be]
  def and_then
    result = yield @value
    return result if result.is_a?(May::Be)

    raise MustReturnMayBeError, "Expected a May::Be but got #{result.class}"
  end

  # @return [May::Some]
  def map
    result = yield @value
    return self.class.new(result) unless result.nil?

    raise UnexpectedNilError, 'Unexpectedly got a nil'
  end

  # @return [May::Some]
  def or_else
    self
  end

  # @return [String]
  def get_or_else
    @value
  end

  # @param _ [void]
  # @return [String]
  def get_or_else_value(_)
    @value
  end

  def assign(key)
    raise ValueMustBeHashError unless @value.is_a?(Hash)

    result = yield @value
    return result.map { |r| @value.merge(key => r) } if result.is_a?(May::Be)

    raise MustReturnMayBeError, "Expected a May::Be but got #{result.class}"
  end

  def effect
    yield @value
    self
  end

  def or_effect
    self
  end

  def to_json(*)
    {
      kind: 'some',
      value: @value.to_json,
    }.to_json
  end
end

class May::None < May::Be
  # @return [self]
  def and_then
    self
  end

  # @return [self]
  def map
    self
  end

  # @return [May::Be]
  def or_else
    result = yield
    return result if result.is_a?(May::Be)

    raise MustReturnMayBeError, "Expected a May::Be but got #{result.class}"
  end

  # @return [String]
  def get_or_else
    yield
  end

  # @param value [String]
  # @return [String]
  def get_or_else_value(value)
    value
  end

  def assign(_key)
    self
  end

  def effect
    self
  end

  def or_effect
    yield
    self
  end

  def to_json(*)
    {
      kind: 'none',
    }.to_json
  end
end

# Example usage:
#
# # @param num [Integer]
# # @param den [String]
# # @return [May::Be]
# def safe_div(num, den)
#   den == 0 ? May::None.new : May::Some.new(num / den)
# end
#
# puts safe_div(1, 0).get_or_else_value(3)
