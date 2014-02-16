require 'rbs/lexer/definition'

module RBS
  class Token
    attr_reader :name, :value, :line, :column

    def initialize(name, value = nil, line = nil, column = nil)
      @name, @value, @line, @column = name.to_sym, value, line, column
    end

    def is(type)
      case type.to_sym
      when :keyword  then KEYWORDS.include?(name)
      when :operator then OPERATORS.include?(name)
      when :argument then ARGUMENT.include?(name)
      else name == type.to_sym
      end
    end

    def ===(type)
      if type.is_a?(Array)
        type.any? { |t| is(t) }
      else
        is(type)
      end
    end

    def inspect
      val = value unless value.nil? || value == name.to_s
      '[' + [name, val].compact.join(' ') + ']'
    end
  end
end
