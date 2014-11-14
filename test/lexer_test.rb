require 'test_helper'
require 'rbs/lexer'

class RBS::LexerTest < Minitest::Test
  def test_initialize
    lexer = RBS::Lexer.new('1 + 2')
    assert_equal '1 + 2', lexer.input
    assert_equal 1, lexer.line
    assert_equal 1, lexer.column
    assert_instance_of RBS::State, lexer.state
  end

  def test_lex
    lexer = RBS::Lexer.new('123 + 45')
    assert_token [:NUMBER, '123', 1, 1], lexer.lex
    assert_token :whitespace, lexer.lex
    assert_token [:'+', '+', 1, 5], lexer.lex
    assert_token :whitespace, lexer.lex
    assert_token [:NUMBER, '45', 1, 7], lexer.lex
    assert_token :EOF, lexer.lex
    assert_nil lexer.lex
  end

  def test_unknown_token_error
    e = assert_raises(RBS::ParseError) { RBS::Lexer.new("ùa += 1").lex }
    assert_equal "Unknown token ùa at 1,1", e.message
  end

  def test_linefeeds
    lexer = RBS::Lexer.new("\n   \n")
    assert_token [:LF, nil, 1, 1], lexer.lex
    assert_equal :whitespace, lexer.lex.name
    assert_token [:LF, nil, 2, 4], lexer.lex
  end

  def test_comment
    token = RBS::Lexer.new("# this is a comment").lex
    assert_equal :COMMENT, token.name
    assert_equal "# this is a comment", token.value
  end

  def test_multiline_comment
    token = RBS::Lexer.new("# this is a comment\n# on multiple lines").lex
    assert_equal :COMMENT, token.name
    assert_equal "# this is a comment\n# on multiple lines", token.value
  end

  def test_integer_numbers
    assert_token [:NUMBER, '123'],     RBS::Lexer.new("123").lex
    assert_token [:NUMBER, '123e+10'], RBS::Lexer.new("123e+10").lex
    assert_token [:NUMBER, '3E-100'],  RBS::Lexer.new("3E-100").lex
  end

  def test_float_numbers
    assert_token [:NUMBER, '12.345'], RBS::Lexer.new("12.345").lex
    assert_token [:NUMBER, '.123'],   RBS::Lexer.new(".123").lex
    assert_token [:NUMBER, '.3e4'],   RBS::Lexer.new(".3e4").lex
  end

  def test_non_float_numbers
    assert_equal ['1', '.'],       RBS::Lexer.new("1.").tokens.map(&:value).compact
    assert_equal ['1', '.', 'e4'], RBS::Lexer.new("1.e4").tokens.map(&:value).compact
  end

  def test_identifiers
    assert_token [:identifier, 'request'], RBS::Lexer.new('request').lex
    assert_token [:identifier, '$'], RBS::Lexer.new('$').lex
    assert_token [:identifier, 'scope$'], RBS::Lexer.new('scope$').lex
    assert_token [:identifier, 'keep_me_underscored'], RBS::Lexer.new('keep_me_underscored').lex

    assert_token_values %w(a list of words), RBS::Lexer.new('a list of words').tokens
  end

  def test_strings
    assert_token [:STRING, 'a string'], RBS::Lexer.new('"a string"').lex
    assert_token [:STRING, 'a single quoted string'], RBS::Lexer.new("'a single quoted string'").lex

    e = assert_raises(RBS::ParseError) { RBS::Lexer.new("'an unterminated string").lex }
    assert_equal "Unterminated string", e.message
  end

  def test_multiline_strings
    assert_token [:STRING, "a string that spans\non multiple lines"],
      RBS::Lexer.new("'a string that spans\non multiple lines'").lex

    assert_token [:STRING, "a string\n that spans\non multiple  \nlines"],
      RBS::Lexer.new("'a string\n that spans\non multiple  \nlines'").lex
  end

  def test_interpolation_in_strings
    assert_token_values %w(( "hello\ " + ( name ) )),
      RBS::Lexer.new('"hello #{name}"').tokens

    assert_token_values %w(( "hello\ " + ( title ) + "\ " + ( name ) )),
      RBS::Lexer.new('"hello #{title} #{name}"').tokens

    assert_token_values %w(( "hello\ " + ( title + name ) )),
      RBS::Lexer.new('"hello #{title + name}"').tokens

    assert_token_values %w(replace ( ( "hello\ " + ( world ) + "!" ) ) . slice ( 0 )),
      RBS::Lexer.new('replace("hello #{world}!").slice(0)').tokens
  end

  def test_no_interpolation_for_single_quoted_string
    assert_token [:STRING, 'hello #{name}'], RBS::Lexer.new('\'hello #{name}\'').lex
  end

  def test_string_in_interpolation
    assert_token_values %w(( "hello\ " + ( "title" ) )),
      RBS::Lexer.new('"hello #{"title"}"').tokens

    assert_token_values %w(( "hello\ " + ( "title" + "name" ) )),
      RBS::Lexer.new('"hello #{"title" + "name"}"').tokens
  end

  def test_chaining_on_interpolated_string
    assert_token_values %w(( "hello\ " + ( name ) ) . slice ( 7 )),
      RBS::Lexer.new('"hello #{name}".slice(7)').tokens

    assert_token_values %w(( "hello\ " + ( name ) ) [ 8 ] ),
      RBS::Lexer.new('"hello #{name}"[8]').tokens
  end

  def test_string_interpolation_state_must_be_popped
    assert_token_values %w(-> { console . log ( ( "download\ " + ( code ) + "\ into\ " + ( directoryEntry ) ) ) }),
      RBS::Lexer.new('-> { console.log("download #{code} into #{directoryEntry}") }').tokens
  end

  def test_modulo_operator_isnt_a_literal
    assert_token [:'%', '%'], RBS::Lexer.new("% ").lex
    assert_token [:'%=', '%='], RBS::Lexer.new("%=").lex
  end

  def test_string_literal
    assert_token [:STRING, 'string'], RBS::Lexer.new("%(string)").lex
    assert_token [:STRING, 'string'], RBS::Lexer.new("%$string$").lex
    assert_token [:STRING, 'string'], RBS::Lexer.new("%|string|").lex
    assert_token [:STRING, 'another string'], RBS::Lexer.new("%{another string}").lex

    e = assert_raises(RBS::ParseError) { RBS::Lexer.new("%(an unterminated string").lex }
    assert_equal "Unterminated string", e.message
  end

  def test_quotes_in_string_literal
    assert_token [:STRING, %(a 'quoted' string)], RBS::Lexer.new("%{a 'quoted' string}").lex

    assert_token [:STRING, %(another "quoted" string)],
      RBS::Lexer.new('%{another "quoted" string}').lex

    assert_token [:STRING, %(a 'single quoted' and "quoted" string)],
      RBS::Lexer.new(%(%{a 'single quoted' and "quoted" string})).lex

    assert_token [:STRING, %(string with "quotes" and 'single quotes')],
      RBS::Lexer.new("%{string with \"quotes\" and 'single quotes'}").lex
  end

  def test_interpolation_in_string_literal
    assert_token_values %w(( "string\ with\ " + ( interpolation ) )),
      RBS::Lexer.new('%(string with #{interpolation})').tokens
  end

  def test_regexp_literal
    assert_token [:REGEXP, "/foo (bar|baz)/"], RBS::Lexer.new("/foo (bar|baz)/").lex
    assert_token [:REGEXP, "/<.+?>/"], RBS::Lexer.new("/<.+?>/").lex
    assert_token [:REGEXP, "/\\/path\\/to/"], RBS::Lexer.new('/\/path\/to/').lex
    assert_token_values %w(/^$/ . test ( str )), RBS::Lexer.new('/^$/.test(str)').tokens
  end

  def test_regexp_literal_options
    assert_token [:REGEXP, "/foo/i"], RBS::Lexer.new('/foo/i').lex
    assert_token [:REGEXP, "/.+/igym"], RBS::Lexer.new('/.+/igym').lex
  end

  def test_regexp_r_literal
    assert_token [:REGEXP, '/\\/path\\/to\\/somewhere/'],
      RBS::Lexer.new("%r(/path/to/somewhere)").lex

    assert_token [:REGEXP, '/\\/path/ig'],
      RBS::Lexer.new("%r{/path}ig").lex
  end

  def test_words_literal
    assert_token_values %w([ "first" "second" "third" ]),
      RBS::Lexer.new("%w(first second third)").tokens

    assert_token_values %w([ "first" "second" "third" ]),
      RBS::Lexer.new("%w{  \n first second \n third  }").tokens
  end
end
