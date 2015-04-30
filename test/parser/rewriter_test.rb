require "test_helper"
require "rbs/parser/rewriter"

class RBS::Parser::RewriterTest < Minitest::Test
  def test_return_last_expression_in_function_statement
    assert_statement({ block: { body: [:return_statement] } }, "def a; b; end")
    assert_statement({ block: { body: [:expression_statement, :return_statement] } }, "def a; b; c; end")
    assert_expression({ arguments: [block: { body: [:return_statement] }] }, "ary.map ->(b) { b.call() }")
    assert_statement({ body: [{ block: { body: [:return_statement] } }] }, "object A; def b; c; end; end")
  end

  def test_returns_last_expression_in_rescued_function_statements
    assert_statement({ block: {
      block: { body: [:return_statement] },
      handlers: [{ body: [:return_statement] }],
      finalizer: { body: [:return_statement] },
    } }, "def a; b(); rescue; c; ensure; d; end")
  end

  def test_return_last_expression_in_object_and_class_methods_but_not_class_constructor
    assert_statement({ body: [
      { block: { body: [:return_statement] } },
      { block: { body: [:return_statement] } },
    ]}, "object A; def constructor; e; end; def b; c; end; end")

    assert_statement({ body: [
      { block: { body: [:expression_statement] } },
      { block: { body: [:return_statement] } },
    ]}, "class A; def constructor; e; end; def b; c; end; end")
  end

  def test_returns_last_expression_in_lambda_statement
    code =  "def a; -> { b; c; }; end"
    assert_statement({ block: { body: [:return_statement] } }, code)
    assert_statement({ block: { body: [{ argument: :lambda_expression }] } }, code)
    assert_statement({ block: { body: [{ argument: { block: { body: [:expression_statement, :return_statement] } } }] } }, code)
  end

  def test_returns_last_expression_within_conditional_statement
    assert_statement(
      { block: { body: [{ consequent: { body: [:return_statement] } }] } },
      "def x; unless y; 1; end; end")

    assert_statement(
      { block: { body: [{
        consequent: { body: [:return_statement] },
        alternate: {
          consequent: { body: [:return_statement], },
          alternate: { body: [:return_statement] },
        },
      }] } },
      "def x; if y; 1; elsif z; 2; else 3; end; end")

    assert_statement(
      { block: { body: [{
        cases: [{ consequent: { body: [:return_statement] } }],
        alternate: { body: [:return_statement] },
      }] } },
      "def x; case y; when z; 2; else 3; end; end")

    assert_statement({ block: { body: [{
      block: { body: [:return_statement] },
      handlers: [{ body: [:return_statement] }],
      finalizer: { body: [:return_statement] },
     }] } }, "def a; begin; b(); rescue; c; ensure; d; end; end")
  end

  def test_recursively_returns_last_expression_within_mixed_conditional_statements
    code = <<-RBS
    def test(x)
      case x
      when 1
        if f(x) > 10
          x - 10
        else
          x + 10
        end
      when 2
        10 unless f(x) < 20
      when 3
      else
        0
      end
    end
    RBS

    assert_statement({ block: { body: [{
      cases: [
        { consequent: { body: [{ consequent: { body: [:return_statement] }, alternate: { body: [:return_statement] } }] }},
        { consequent: { body: [{ consequent: { body: [:return_statement] } }] }},
        {},
      ]
    }] } }, code)
  end

  def test_rewrites_unless_statement_as_if_statement
    assert_statement :if_statement, "unless x; end"
    assert_statement({ test: :unary_expression }, "unless x; end")

    with_experimental(true) do
      assert_statement({ test: :binary_expression }, "unless x > 10; end")
    end
  end

  def test_rewrites_until_statement_as_while_statement
    assert_statement :while_statement, "until x; end"
    assert_statement({ test: :unary_expression }, "until x; end")

    with_experimental(true) do
      assert_statement({ test: :binary_expression }, "until x > 10; end")
    end
  end
end
