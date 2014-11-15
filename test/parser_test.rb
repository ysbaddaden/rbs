require 'test_helper'
require 'rbs/lexer'
require 'rbs/lexer/rewriter'
require 'rbs/parser'

class RBS::ParserTest < Minitest::Test
  def test_parse
    program = parse("a = 1\n b = 'str'; c = \"str2\"")
    assert_equal :program, program.type
    assert_ast({ :body => %i(expression_statement expression_statement expression_statement) }, program)
  end

  def test_empty_statement
    assert_statement :empty_statement, ";"
    assert_statement :empty_statement, "\n"
  end

  def test_expression_statement
    assert_statement :expression_statement, "a = 1"
    assert_statement :expression_statement, "a * b + c / 1"
  end

  def test_primary_expression
    assert_expression :identifier, "foo"

    assert_expression :literal, "nil"
    assert_expression :literal, "true"
    assert_expression :literal, "false"

    assert_expression :literal, "1"
    assert_expression :literal, "1.2"
    assert_expression :literal, ".2"

    assert_expression :literal, "'str'"
    assert_expression :literal, '"str2"'

    assert_expression :literal, '/\w+/'
  end

  def test_array_expression
    assert_expression :array_expression, "[]"
    assert_expression :array_expression, "[1, 2]"
    assert_expression({ elements: %i(literal literal literal) }, "[1, 2, 3, ]")
  end

  def test_object_expression
    assert_expression :object_expression, "{}"
    assert_expression :object_expression, "{ a: 1 }"
    assert_expression({ properties: %i(property property) }, "{ a: 1, b: 2, }")
    assert_expression({ properties: [{ key: :identifier, value: :literal } ] }, "{ a: 1 }")
  end

  def test_unary_expression
    RBS::UNARY_OPERATOR.each do |op|
      assert_expression :unary_expression, "#{op} a"
    end
  end

  def test_member_expression
    assert_expression :member_expression, "obj.prop"
    assert_expression :member_expression, "a.b.c"
    assert_expression({ computed: false, object: :identifier, property: :identifier }, "obj.prop")
    assert_expression({ computed: false, object: :member_expression, property: :identifier }, "a.b.c")

    assert_expression :member_expression, "obj[prop]"
    assert_expression({ computed: true, object: :identifier, property: :identifier }, "obj[prop]")
    assert_expression({ computed: true, object: :identifier, property: :binary_expression }, "obj[a * b]")
  end

  def test_call_expression
    assert_expression :call_expression, "a()"
    assert_expression :call_expression, "obj.something()"
    assert_expression :call_expression, "obj[something]()"

    assert_expression({ callee: :identifier, arguments: [] }, "some()")
    assert_expression({ callee: :identifier, arguments: [:identifier, :identifier] }, "some(arg1, arg2)")

    assert_expression({ arguments: [:splat_expression] }, "some(*arg)")
    assert_expression({ arguments: [:identifier, :identifier, :splat_expression] }, "some(i, j, *arg)")
    assert_expression({ arguments: [:splat_expression, :identifier] }, "some(*arg, i)")

    assert_expression({ arguments: [:object_expression] }, "some(a: 1, b: 2)")
    assert_expression({ arguments: [:identifier, :splat_expression, :object_expression] }, "some(x, *ary, a: 1, b: 2)")
  end

  def test_assignment_expression
    RBS::ASSIGNMENT_OPERATOR.each do |op|
      assert_expression :assignment_expression, "a #{op} 1"
    end
  end

  def test_binary_expression
    RBS::BINARY_OPERATOR.each do |op|
      assert_expression :binary_expression, "a #{op} b"
    end
  end

  def parse(code)
    RBS::Parser.new(RBS::Rewriter.new(RBS::Lexer.new(code))).parse
  end
end
