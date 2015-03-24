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

  def test_return_statement
    assert_format "return;", "return"
    assert_format "return a;", "return a"
    assert_format "return (d);", "return (d)"
  end

  def test_delete_statement
    assert_format "delete a.b.c;", "delete a.b.c"
    assert_format "delete a[b];", "delete a[b]"
  end

  def test_loop_flow_statements
    assert_format "continue;", "next"
    assert_format "break;", "break"
  end

  def test_if_statement
    assert_format "if (test) {}", "if test; end"
    assert_format "if (a == b) {}", "if (a == b); end"
    assert_format "if (test) { a; b; c; }", "if test; a; b; c; end"

    assert_format "if (test) {} else {}", "if test; else; end"
    assert_format "if (test) {} else { b; a; }", "if test; else; b; a; end"

    assert_format "if (a) {} else if (b) {} else {}", "if a; elsif b; else; end"
    assert_format "if (a) {} else if (b) {} else if (c) {} else {}", "if a; elsif b; elsif c; else; end"
  end

  def test_unless_statement
    assert_format "if (!test) {}", "unless test; end"
    assert_format "if (!test) { d; c; b; }", "unless test; d; c; b; end"
    assert_format "if (a) {}", "unless !a; end"

    assert_format "if (a > b) {}", "unless !(a > b); end"
    assert_format "if (!(a > b)) {}", "unless (a > b); end"

    assert_format "if (!(a && b)) {}", "unless a && b; end"
    assert_format "if (!(a && !b && c)) {}", "unless a && !b && c; end"
    assert_format "if (!((a && b) || !(c && d))) {}", "unless (a && b) || !(c && d); end"
    assert_format "if (!(!a > b)) {}", "unless !a > b; end"

    #assert_format "if (a <= b) {}", "unless a > b; end"
    #assert_format "if (a < b) {}",  "unless a >= b; end"
    #assert_format "if (a == b) {}", "unless a != b; end"
    #assert_format "if (a != b) {}", "unless a == b; end"
    #assert_format "if (a >= b) {}", "unless a < b; end"
    #assert_format "if (a <= b) {}", "unless a > b; end"
    #assert_format "if (a > b) {}",  "unless a <= b; end"
    #assert_format "if (a < b) {}",  "unless a >= b; end"

    #assert_format "if (!a || !b) {}", "unless a && b; end"
    #assert_format "if (!a || b || !c) {}", "unless a && !b && c; end"
    #assert_format "if (!(a && b) && (c && d)) {}", "unless (a && b) || !(c && d); end"

    #assert_format "if (a >= b && c || !d) {}", "unless a < b || !c && d; end"
    #assert_format "if (a != b && c != d) {}", "unless a == b || c == d; end"
    #assert_format "if (a != b && c <= d && e > f) {}", "unless a == b || c > d || e <= f; end"

    #assert_format "if (!a <= b) {}", "unless !a > b; end"
    #assert_format "if (!a != b || c >= d) {}", "unless !a == b && c < d; end"
  end

  def test_case_statement
    assert_format "switch (x) { case 1: break; case 2: case 3: break; }", "case x; when 1; when 2, 3; end"
    assert_format "switch (x) { case 1: some(); break; case 2: case 3: thing(); more(); break; }", "case x; when 1; some(); when 2, 3; thing(); more(); end"
    assert_format "switch (x) { case 1: break; default: y; }", "case x; when 1; else; y; end"
    assert_format "switch (x) { case 1: return; default: y; }", "case x; when 1; return; else; y; end"
  end

  def test_while_statement
    assert_format "while (test) {}", "while test; end"
    assert_format "while (a == b) {}", "while (a == b); end"
    assert_format "while (test) { a; b; c; }", "while test; a; b; c; end"
  end

  def test_until_statement
    assert_format "while (!test) {}", "until test; end"
    assert_format "while (!test) { d; c; b; }", "until test; d; c; b; end"
    assert_format "while (a) {}", "until !a; end"

    assert_format "while (a > b) {}", "until !(a > b); end"
    assert_format "while (!(a > b)) {}", "until (a > b); end"

    assert_format "while (!(a && b)) {}", "until a && b; end"
    assert_format "while (!(a && !b && c)) {}", "until a && !b && c; end"
    assert_format "while (!((a && b) || !(c && d))) {}", "until (a && b) || !(c && d); end"
    assert_format "while (!(!a > b)) {}", "until !a > b; end"
  end

  def test_loop_statement
    assert_format "while (1) {}", "loop; end"
    assert_format "while (1) { if (t()) { break; } }", "loop; break if t(); end"
  end

  def test_rescue_statement
    ex = "__rbs_exception"

    assert_format "try { x; } catch (#{ex}) { throw #{ex}; }",
      "begin; x; end"

    assert_format "try { x; } catch (#{ex}) {}",
      "begin; x; rescue; end"

    assert_format "try { x; } catch (#{ex}) { y; }",
      "begin; x; rescue; y; end"

    assert_format "try { x; } catch (#{ex}) { if (#{ex} instanceof A) {} else { throw #{ex}; } }",
      "begin; x; rescue A; end"

    assert_format "try { x; } catch (#{ex}) { if (#{ex} instanceof A) {} else if (#{ex} instanceof B) {} else { throw #{ex}; } }",
      "begin; x; rescue A; rescue B; end"

    assert_format "try { x; } catch (#{ex}) { if (#{ex} instanceof A || #{ex} instanceof B) {} else { throw #{ex}; } }",
      "begin; x; rescue A, B; end"

    assert_format "try { x; } catch (#{ex}) { if (#{ex} instanceof C) {} else {} }",
      "begin; x; rescue C; rescue; end"

    assert_format "try { x; } catch (#{ex}) { if (#{ex} instanceof D) {} else { y; } }",
      "begin; x; rescue D; rescue; y; end"
  end

  def test_exception_var_in_rescue_statements
    ex = "__rbs_exception"

    assert_format "try { x; } catch (ex) { y(ex); }",
      "begin; x; rescue => ex; y(ex); end"

    assert_format "try { x; } catch (exc) { if (exc instanceof A) {} else if (exc instanceof B) {} else { throw exc; } }",
      "begin; x; rescue A => exc; rescue B => exc; end"

    assert_format "try { x; } catch (#{ex}) { var ex1, ex2; if (#{ex} instanceof A) {} else if (#{ex} instanceof B) {} else { throw #{ex}; } }",
      "begin; x; rescue A => ex1; rescue B => ex2; end"

    assert_format "try { x; } catch (#{ex}) { var e1, e2; if (#{ex} instanceof A) { e1 = #{ex}; y(e1); } else if (#{ex} instanceof B) { e2 = #{ex}; y(e2); } else { throw #{ex}; } }",
      "begin; x; rescue A => e1; y(e1); rescue B => e2; y(e2); end"
  end

  def test_ensure_in_rescue_statements
    ex = "__rbs_exception"

    assert_format "try { x; } finally {}",
      "begin; x; ensure; end"

    assert_format "try { x; } catch (#{ex}) {} finally { y; }",
      "begin; x; rescue; ensure; y; end"
  end

  def test_function_statement
    assert_format "function a() {}", "def a; end"
    assert_format "function a() { y; z; }", "def a; y; z; end"

    assert_format "a.b.c.d = function () {}", "def a.b.c.d; end"
    assert_format "a[x] = function () {}", "def a[x]; end"
    assert_format "a[0].z = function () {}", "def a[0].z; end"

    assert_format "function a(b, c, d) {}", "def a(b, c, d) end"

    assert_format "function a() { var b = Array.prototype.slice.call(arguments); }",
      "def a(*b) end"

    assert_format "function a(b, c) { var d = Array.prototype.slice.call(arguments, 2); }",
      "def a(b, c, *d) end"

    assert_format "function a(b) { var d = Array.prototype.slice.call(arguments, 1, -1); var e = arguments[arguments.length - 1]; }",
      "def a(b, *d, e) end"
  end
end
