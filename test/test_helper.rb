require 'pp'
require 'bundler'
Bundler.require(:default, :test)
require "minitest/autorun"
require "minitest/mock"
require "rbs"

class Minitest::Test
  def experimental
    false
  end

  def with_experimental(bool = true)
    stub(:experimental, bool) { yield }
  end


  def lex(code)
    RBS::Lexer::Rewriter.new(RBS::Lexer.new(code))
  end

  def parse(code, rewrite: true)
    parser = RBS::Parser.new(lex(code))
    parser = RBS::Parser::Rewriter.new(parser) if rewrite
    parser.parse(experimental: experimental)
  end

  def format(code, type: "raw")
    parser = RBS::Parser::Rewriter.new(RBS::Parser.new(lex(code)))
    RBS::Formatter.new(parser).compile(type: "raw", experimental: experimental)
  end


  def assert_token(expected, actual)
    if expected.is_a?(Array)
      assert_equal expected,
        [actual.name, actual.value, actual.line, actual.column].slice(0...expected.size)
    else
      assert_equal expected, actual.name
    end
  end

  def assert_tokens(expected, actual)
    assert_equal expected.map(&:to_sym), actual.map(&:name)
  end

  def assert_token_values(expected, actual)
    assert_equal expected, actual
      .reject { |t| t === :whitespace }
      .map { |t| t === :STRING ? t.value.inspect : t.value }
      .compact
  end


  def assert_ast(expected, expression)
    case expected
    when Symbol, String
      if expression.respond_to?(:type)
        assert_equal expected.to_sym, expression.type
      else
        assert_equal expected, expression
      end
    when Hash
      expected.each do |param, expect|
        assert_respond_to expression, param.to_sym
        assert_ast expect, expression.__send__(param)
      end
    when Array
      assert_instance_of Array, expression
      assert_equal expected.size, expression.size,
        "Expected #{expression} to have #{expected.size} items, but was #{expression.size}"

      expected.each_with_index do |expect, index|
        assert_ast expect, expression[index]
      end
    when true
      assert expression
    when false
      refute expression
    else
      flunk "unknown expected: #{expected}"
    end
  end

  def assert_expression(expected, code)
    assert_ast expected, parse(code).body.first.expression
  end

  def assert_statement(expected, code)
    assert_ast expected, parse(code).body.first
  end


  def assert_format(expected, code)
    formatted = format(code).gsub(/\s+/, " ").strip()
    case expected
    when Regexp
      assert_match expected, formatted
    else
      assert_equal expected, formatted
    end
  end
end
