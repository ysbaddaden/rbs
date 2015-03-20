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

  def test_def_statement
    assert_statement :function_statement, "def f; end"
    assert_statement :function_statement, "def f() end"
    assert_statement :function_statement, "def f(a, b, c) end"
    assert_statement :function_statement, "def f a, b, c; end"
    assert_raises(RBS::SyntaxError) { parse("def f(x, x) end") }

    assert_statement :function_statement, "def f(*args) end"
    assert_statement :function_statement, "def f(*args, options) end"
    assert_statement :function_statement, "def f(x, *args) end"
    assert_statement :function_statement, "def f(x, *args, options) end"
    assert_raises(RBS::ParseError) { parse("def f(*x, *y) end") }
  end

  def test_object_statement
    assert_statement :object_statement, "object X; end"
    assert_statement({ id: :identifier, body: [] }, "object Name; end")
    assert_statement({ body: [:object_statement] }, "object A; object B; end; end")

    assert_statement({ body: [:function_statement, :function_statement] }, "object X; def foo; end; def bar() end end")
    assert_statement({ body: [:property, :function_statement] }, "object X; foo = 1; def getFoo() end end")
    assert_raises(RBS::ParseError) { parse("object X; self.foo = 1; end") }
    assert_raises(RBS::ParseError) { parse("object X; def self.getFoo; end end") }
  end

  def test_rescue_statements
    assert_statement :try_statement, "begin;end"
    assert_statement :try_statement, "begin;rescue;end"
    assert_statement :try_statement, "begin;ensure;end"
    assert_statement :try_statement, "begin;rescue;ensure;end"

    assert_statement({ block: :block_statement, handlers: [:catch_clause] }, "begin; test(); rescue; end")
    assert_statement({ block: :block_statement, handlers: [:catch_clause, :catch_clause] }, "begin; rescue; rescue; end")
    assert_statement({ handlers: [{ body: [:expression_statement] }] }, "begin; rescue; cleanup(); end")
    assert_statement({ finalizer: :block_statement }, "begin; ensure; cleanup(); end")

    assert_statement({ handlers: [:catch_clause, :catch_clause, :catch_clause] }, "begin; rescue A; rescue B; rescue B; end")
    assert_statement({ handlers: [{ class_names: %i(identifier) }] }, "begin; rescue A; end")
    assert_statement({ handlers: [{ class_names: %i(identifier identifier identifier) }] }, "begin; rescue A, B, C; end")
    assert_statement({ handlers: [{ param: :identifier }] }, "begin; rescue A, B, C => e; end")
  end

  def test_rescue_statements_in_def_statement
    assert_statement :function_statement, "def fn; rescue; end"
    assert_statement :function_statement, "def fn; ensure; end"
    assert_statement :function_statement, "def fn; rescue; ensure; end"
    assert_statement :function_statement, "def fn; rescue A; rescue B; ensure; end"

    assert_statement({ block: :try_statement }, "def fn; test(); rescue; end")
    assert_statement({ block: { handlers: [:catch_clause], finalizer: :block_statement } }, "def fn; test(); rescue; ensure; end")
  end

  def test_if_statement
    assert_statement :if_statement, "if x; y; end"
    assert_statement :if_statement, "if x then y end"
    assert_ast [:if_statement, :expression_statement], parse("if x then y end; a = b").body

    assert_statement({ test: :binary_expression, consequent: { body: [:expression_statement] } }, "if x + 2 > z then y end")

    assert_statement :if_statement, "if x; y; else; z; end"
    assert_statement({ consequent: :block_statement, alternate: { body: [:expression_statement] } }, "if x then y else z end")

    assert_statement :if_statement, "if a then b elsif c then d else e end"
    assert_statement :if_statement, "if a then b elsif c then d elsif e then f else g end"

    code = "if a then b elsif c then d elsif e then f else g end"
    assert_statement({ alternate: :if_statement }, code)
    assert_statement({ alternate: { alternate: :if_statement } }, code)
    assert_statement({ alternate: { alternate: { alternate: :block_statement } } }, code)
  end

  def test_unless_statement
    assert_statement :unless_statement, "unless x; y; end"
    assert_ast [:unless_statement, :expression_statement], parse("unless x then y end; a").body
    assert_statement({ test: :binary_expression, consequent: { body: [:expression_statement] } }, "unless x + 1 then y end")
  end

  def test_while_statement
    assert_statement :while_statement, "while x; y; end"
    assert_ast [:while_statement, :expression_statement], parse("while x do y end; a").body
    assert_statement({ test: :binary_expression, consequent: { body: [:expression_statement] } }, "while x + 1 do y end")
  end

  def test_until_statement
    assert_statement :until_statement, "until x; y; end"
    assert_ast [:until_statement, :expression_statement], parse("until x do y end; a").body
    assert_statement({ test: :binary_expression, consequent: { body: [:expression_statement] } }, "until x + 1 do y end")
  end

  def test_loop_statement
    assert_statement :loop_statement, "loop; run(); end"
    assert_ast [:loop_statement, :expression_statement], parse("loop do worker.handle(socket) end; a").body
    assert_statement({ consequent: { body: [:expression_statement] } }, "loop do worker.handle(socket) end")
  end

  def test_case_statement
    assert_statement :case_statement, "case x; when 1; end"
    assert_statement({ test: :binary_expression, cases: [:when_statement] }, "case x + 1 when 1 end")
    assert_statement({ cases: [:when_statement, :when_statement, :when_statement] }, "case x + 1; when 1; when 2; when 3; end")
    assert_statement({ cases: [{ tests: [:call_expression] }] }, "case x + 1; when y(); end")
    assert_statement({ cases: [{ tests: [:identifier, :literal, :literal] }] }, "case x + 1; when y, 2, 3; z() end")
    assert_statement({ cases: [{ consequent: :block_statement }] }, "case x + 1; when y, 2, 3; z() end")
    assert_statement({ cases: [{ consequent: :block_statement }] }, "case x when 1 then z() end")
  end

  def test_control_statement
    assert_statement :break_statement, "break"
    assert_statement :next_statement, "next"
  end

  def test_return_statement
    assert_statement :return_statement, "return"
    assert_statement :return_statement, "return value"
    assert_statement({ argument: :identifier }, "return value")
    assert_statement({ argument: :binary_expression }, "return 1 + 2 * 4")
  end

  def test_delete_statement
    assert_statement :delete_statement, "delete value"
    assert_statement({ argument: :identifier }, "delete value")
  end

  def test_expression_statement
    assert_statement :expression_statement, "a = 1"
    assert_statement :expression_statement, "a * b + c / 1"
  end

  def test_statement_modifiers
    assert_statement :if_statement, "tom if jerry"
    assert_statement({ test: :call_expression, consequent: :block_statement }, "a += 1 if match(a)")
    assert_statement({ test: :identifier, consequent: { body: [:assignment_expression] } }, "a += 1 if increment")

    assert_statement :unless_statement, "tom unless jerry"
    assert_statement({ test: :identifier, consequent: :block_statement }, "tom unless jerry")
    assert_statement({ test: :identifier, consequent: { body: [:identifier] } }, "tom unless coyote")

    assert_statement :while_statement, "tom while jerry"
    assert_statement({ test: :identifier, consequent: :block_statement }, "tom unless jerry")

    assert_statement :until_statement, "tom until jerry"
    assert_statement({ test: :identifier, consequent: :block_statement }, "tom unless jerry")
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

    assert_expression({ arguments: [:object_expression, :literal] }, "fn({ x: 1 }, 2)")
    assert_raises(RBS::ParseError) { parse("fn(x: 1, 2)") }
    assert_raises(RBS::ParseError) { parse("fn(x: 1, *args)") }

    assert_expression :call_expression, "some thing"
    assert_expression({ arguments: [:identifier] }, "some thing")
    assert_expression({ arguments: [:identifier, :identifier] }, "some thing, more")
    assert_expression({ arguments: [:array_expression] }, "some [1, 2]")
    assert_expression({ arguments: [:object_expression] }, "some { thing: more }")
    assert_expression({ arguments: [:object_expression] }, "some thing: more")
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
