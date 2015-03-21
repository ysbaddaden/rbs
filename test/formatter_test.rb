require 'test_helper'
require 'rbs/lexer'
require 'rbs/lexer/rewriter'
require 'rbs/parser'
require 'rbs/formatter'

class RBS::FormatterTest < Minitest::Test
  def test_literal
    assert_format "true;", "true"
    assert_format "false;", "false"
    assert_format "nil;", "nil"
    assert_format "null;", "null"
    assert_format "undefined;", "undefined"

    assert_format "1;", "1"
    assert_format "11287.123;", "11287.123"

    assert_format "'a string';", "'a string'"
    assert_format "'a double quoted string';", '"a double quoted string"'

    assert_format "/foo(bar)/;", "/foo(bar)/"
    assert_format "/\w+/ig;", "/\w+/ig"

    assert_format "test;", "test"
    assert_format "ident;", "ident"
  end

  def test_array
    assert_format "[];", "[]"
    assert_format "[1, 2, test, more];", "[1\n,\n 2, test, more]"
    assert_format "[1, 2, test, more];", "[1\n,\n 2, test, more]"
  end

  def test_object
    assert_format "{};", "{}"
    assert_format "{ a: 1, b: c };", "{ a: 1, b: c }"
  end

  def test_group_expression
    assert_format "(a);", "(a)"
    assert_format "(a + b) * 2;", "(a + b) * 2"
  end

  def test_member_expression
    assert_format "a.b.c.d;", "a.b.c.d"
    assert_format "a.b();", "a.b()"
    assert_format "a.b().c.d;", "a.b().c.d"
    assert_format "a[1];", "a[1];"
    assert_format "a[1][c][d];", "a[1][c][d];"
  end

  def test_call_expression
    assert_format "t();", "t()"
    assert_format "some(thing, more);", "some(thing, more)"

    assert_format "some.apply(null, things);", "some(*things)"
    assert_format "some.apply(null, more.concat(splatted, things));", "some(*more, *splatted, *things)"

    assert_format "some.apply(null, [a, b].concat(c));", "some(a, b, *c)"
    assert_format "some.apply(null, [a].concat(b, [c]));", "some(a, *b, c)"
    assert_format "some.apply(null, a.concat([b, c]));", "some(*a, b, c)"
    assert_format "some.apply(null, a.concat([b, c], d));", "some(*a, b, c, *d)"
    assert_format "some.apply(null, a.concat([b, c], d, [e]));", "some(*a, b, c, *d, e)"
    assert_format "some.apply(null, [a].concat(b, [c], d, [e]));", "some(a, *b, c, *d, e)"
  end

  def test_unary_expression
    RBS::UNARY_OPERATOR.each do |op|
      if op == "typeof"
        assert_format "#{op} a;", "#{op} a"
      else
        assert_format "#{op}a;", "#{op}a"
      end
    end
  end

  def test_binary_expression
    RBS::BINARY_OPERATOR.each do |op|
      assert_format "a #{op} b;", "a #{op} b" unless op == ".." || op == "..."
    end
  end

  def test_assignment_expression
    RBS::ASSIGNMENT_OPERATOR.each do |op|
      assert_format "a #{op} b;", "a #{op} b"
    end
  end
end
