require 'test_helper'
require 'rbs/lexer'
require 'rbs/lexer/rewriter'

class RBS::RewriterTest < Minitest::Test
  def test_initialize
    lexer = RBS::Lexer.new("_code_")
    rewriter = RBS::Rewriter.new(lexer)
    assert_same lexer, rewriter.lexer
  end

  def test_lex
    assert_token [:BOOLEAN, 'true'], rewriter("true").lex
  end

  def test_skips_whitespace
    refute rewriter("1 + 2 + 3").tokens.any? { |token| token === :whitespace }
  end

  def test_skips_linefeeds
    assert_tokens %w(identifier and identifier : EOF),
      rewriter("a and \n b  : \n").tokens
  end

  def test_consolidates_linefeeds
    assert_tokens %w(def identifier ( identifier ) LF return identifier + NUMBER LF end EOF),
      rewriter("def A(a)\nreturn a + 1\n \n \n end").tokens
  end

  def test_injects_defn_parens
    assert_tokens %w(def identifier ( identifier , identifier ) LF end EOF),
      rewriter("def x a, b; end").tokens

    assert_tokens %w(def identifier ( identifier = NIL ) LF return identifier + NUMBER LF end EOF),
      rewriter("def A default = nil\nreturn a + 1\n end").tokens
  end

  def test_injects_call_parens
    assert_tokens %w(identifier ( STRING , -> { identifier ( STRING , -> { identifier . identifier ( BOOLEAN ) LF } ) LF } ) EOF),
      rewriter("describe 'DSL', -> {\n  it 'must be ok', -> {\n    assert.ok true\n }\n}").tokens

    assert_tokens %w(-> { identifier . identifier ( identifier ) } EOF),
      rewriter("-> { x.map name }").tokens

    assert_tokens %w(identifier ( STRING ) if identifier . identifier EOF),
      rewriter("log 'event' if options.verbose").tokens

    assert_tokens %w(identifier ( identifier ) for identifier of identifier EOF),
      rewriter("callback value for callback of callbacks").tokens
  end

  def test_edge_cases_for_injecting_call_parens
    assert_tokens %w(identifier ( - NUMBER ) EOF), rewriter("add -1").tokens
    assert_tokens %w(identifier - NUMBER EOF), rewriter("add - 1").tokens
    assert_tokens %w(identifier ( + identifier ) EOF), rewriter("add +x").tokens
    assert_tokens %w(identifier ( ~ identifier ( ) ) EOF), rewriter("add ~doSomething()").tokens
    assert_tokens %w(identifier ( * identifier ) EOF), rewriter("add *args").tokens
    assert_tokens %w(identifier * identifier EOF), rewriter("add * args").tokens
  end

  def test_closes_injected_parens_in_nested_calls
    assert_tokens %w(identifier ( identifier ( -> { } ) ) EOF), rewriter("beforeEach(inject(-> {}))").tokens
    assert_tokens %w(identifier ( identifier ( -> { } ) ) EOF), rewriter("beforeEach inject(-> {})").tokens
    assert_tokens %w(identifier ( identifier ( -> { } ) ) EOF), rewriter("beforeEach(inject -> {})").tokens
    assert_tokens %w(identifier ( identifier ( -> { } ) ) EOF), rewriter("beforeEach inject -> {}").tokens
    assert_tokens %w(identifier . identifier ( -> ( identifier ) { identifier . identifier ( -> { } ) } ) EOF),
      rewriter("ary.map ->(a) { a.map -> {} }").tokens
  end

  def test_dottable_keywords_are_identifiers
    assert_tokens %w(identifier . identifier EOF), rewriter("promise.finally").tokens
    assert_tokens %w(def identifier LF end EOF), rewriter("def delete\nend").tokens
    assert_tokens %w(def + identifier LF end EOF), rewriter("def + delete\nend").tokens
    assert_tokens %w(identifier . identifier EOF), rewriter("a.return").tokens
    assert_tokens %w(identifier : EOF), rewriter("catch:").tokens
  end

  def rewriter(code)
    RBS::Rewriter.new(RBS::Lexer.new(code))
  end
end
