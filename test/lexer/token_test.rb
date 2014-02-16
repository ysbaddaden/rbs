require 'test_helper'
require 'rbs/lexer/token'

class RBS::TokenTest < Minitest::Test
  def test_initialize
    token = RBS::Token.new(:LF)
    assert_equal :LF , token.name
    assert_nil token.value

    token = RBS::Token.new('return', 'return')
    assert_equal :return , token.name
    assert_equal 'return', token.value

    token = RBS::Token.new(:delete, 'delete', 45, 3)
    assert_equal :delete , token.name
    assert_equal 'delete', token.value
    assert_equal 45, token.line
    assert_equal 3, token.column
  end

  def test_is
    assert RBS::Token.new(:LF).is(:LF)
    refute RBS::Token.new(:LF).is(:whitespace)
    assert RBS::Token.new(:whitespace).is('whitespace')
  end

  def test_is_keyword
    assert RBS::Token.new(:return).is(:keyword)
    refute RBS::Token.new(:identifier, 'when').is(:keyword)
  end

  def test_is_operator
    assert RBS::Token.new('+').is(:operator)
    refute RBS::Token.new('def').is(:operator)
  end

  def test_is_argument
    assert RBS::Token.new(:NUMBER, '1').is(:argument)
    refute RBS::Token.new(:def, 'def').is(:argument)
  end

  def test_case_equality
    assert(RBS::Token.new(:LF) === :LF)
    assert(RBS::Token.new(:LF) === 'LF')
    assert(RBS::Token.new(:def, 'def') === :def)
    refute(RBS::Token.new(:def, 'def') === :LF)
  end

  def test_case_equality_against_many_types
    assert RBS::Token.new(:LF) === [:LF, :whitespace]
    assert RBS::Token.new(:whitespace) === [:LF, :whitespace]
    refute RBS::Token.new(:def, 'def') === [:LF, :whitespace]
    assert RBS::Token.new(:def, 'def') === [:LF, :whitespace, 'def']
  end

  def inspect
    assert_equal '[LF]', RBS::Token.new(:LF).inspect
    assert_equal '[def]', RBS::Token.new(:def, 'def').inspect
    assert_equal '[identifier route]', RBS::Token.new(:identifier, 'route').inspect
  end
end
