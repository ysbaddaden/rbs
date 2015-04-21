require 'test_helper'

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

  def test_lambda_expression
    assert_format "function () {};", "-> {}"
    assert_format "function (a, b) {};", "->(a, b) {}"
    assert_format "function () { var a = Array.prototype.slice.call(arguments); };", "->(*a) {}"
    assert_format "list.map(function (x) { return x * 2; });", "list.map ->(x) { return x * 2 }"
  end

  def test_variable_scope_in_lambda_expression
    assert_format "function (x) { var y; y = x * 2; return y; };",
      "->(x) { y = x * 2; return y; }"

    assert_format "var y; y = null; a.map(function (x) { y = x * 2; return y; });",
      "y = null; a.map ->(x) { y = x * 2; return y; }"
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
    assert_format "some({ a: b, c: 1 * 2 });", "some(a: b, c: 1 * 2)"

    assert_format "some.apply(null, things);", "some(*things)"
    assert_format "some.apply(null, [].concat(more, splatted, things));", "some(*more, *splatted, *things)"

    assert_format "some.apply(null, [a, b].concat(c));", "some(a, b, *c)"
    assert_format "some.apply(null, [a].concat(b, [c]));", "some(a, *b, c)"
    assert_format "some.apply(null, [].concat(a, [b, c]));", "some(*a, b, c)"
    assert_format "some.apply(null, [].concat(a, [b, c], d));", "some(*a, b, c, *d)"
    assert_format "some.apply(null, [].concat(a, [b, c], d, [e]));", "some(*a, b, c, *d, e)"
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

  def test_conditional_expression
    assert_format "a ? b : c;", "a ? b : c"
    assert_format "var x; x = a > 10 ? a - 10 : a + 10;", "x = a > 10 ? a - 10 : a + 10"
  end

  def test_assignment_expression
    RBS::ASSIGNMENT_OPERATOR.each do |op|
      assert_format "var a; a #{op} b;", "a #{op} b"
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

    with_experimental(false) do
      assert_format "if (a > b) {}", "unless !(a > b); end"
      assert_format "if (!(a > b)) {}", "unless (a > b); end"

      assert_format "if (!(a && b)) {}", "unless a && b; end"
      assert_format "if (!(a && !b && c)) {}", "unless a && !b && c; end"
      assert_format "if (!((a && b) || !(c && d))) {}", "unless (a && b) || !(c && d); end"
      assert_format "if (!(!a > b)) {}", "unless !a > b; end"
    end

    with_experimental(true) do
      assert_format "if (a <= b) {}", "unless a > b; end"
      assert_format "if (a < b) {}",  "unless a >= b; end"
      assert_format "if (a == b) {}", "unless a != b; end"
      assert_format "if (a != b) {}", "unless a == b; end"
      assert_format "if (a >= b) {}", "unless a < b; end"
      assert_format "if (a <= b) {}", "unless a > b; end"
      assert_format "if (a > b) {}",  "unless a <= b; end"
      assert_format "if (a < b) {}",  "unless a >= b; end"

      assert_format "if (!(a + b)) {}",  "unless a + b; end"
      assert_format "if (!(a & b)) {}",  "unless a & b; end"

      assert_format "if (!a || !b) {}", "unless a && b; end"
      assert_format "if (a || b) {}", "unless !a && !b; end"
      assert_format "if (!a || !b || !c) {}", "unless a && b && c; end"
      assert_format "if (!a || b || !c) {}", "unless a && !b && c; end"
      assert_format "if (!(a && b) && (c && d)) {}", "unless (a && b) || !(c && d); end"

      assert_format "if (a >= b && c || !d) {}", "unless a < b || !c && d; end"
      assert_format "if (a != b && c != d) {}", "unless a == b || c == d; end"
      assert_format "if (a != b && c <= d && e > f) {}", "unless a == b || c > d || e <= f; end"

      assert_format "if (!a <= b) {}", "unless !a > b; end"
      assert_format "if (!a != b || c >= d) {}", "unless !a == b && c < d; end"
    end
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

    with_experimental(false) do
      assert_format "while (a > b) {}", "until !(a > b); end"
      assert_format "while (!(a > b)) {}", "until (a > b); end"

      assert_format "while (!(a && b)) {}", "until a && b; end"
      assert_format "while (!(a && !b && c)) {}", "until a && !b && c; end"
      assert_format "while (!((a && b) || !(c && d))) {}", "until (a && b) || !(c && d); end"
      assert_format "while (!(!a > b)) {}", "until !a > b; end"
    end

    with_experimental(true) do
      assert_format "while (a > b) {}", "until !(a > b); end"
      assert_format "while (a <= b) {}", "until a > b; end"
      assert_format "while (!(a > b)) {}", "until (a > b); end"

      assert_format "while (!a || !b) {}", "until a && b; end"
      assert_format "while (!a || b || !c) {}", "until a && !b && c; end"
      assert_format "while (!(a && b) && (c && d)) {}", "until (a && b) || !(c && d); end"
      assert_format "while (!a <= b) {}", "until !a > b; end"
    end
  end

  def test_loop_statement
    assert_format "while (1) {}", "loop; end"
    assert_format "while (1) { if (t()) { break; } }", "loop; break if t(); end"
  end

  def test_for_in_statement
    assert_format "var key; for (key in obj) {}",
      "for key in obj; end"

    assert_format "var key, value; for (key in obj) { value = obj[key]; }",
      "for key, value in obj; end"

    assert_format "var key, value; for (key in some.deep[obj]) { value = some.deep[obj][key]; }",
      "for key, value in some.deep[obj]; end"
  end

  def test_for_of_statement
    assert_format "var __r1, __r2, value; for (__r1 = 0, __r2 = obj.length; __r1 < __r2; __r1++) { value = obj[__r1]; }",
      "for value of obj; end"

    assert_format "var __r1, i, value; for (i = 0, __r1 = obj.length; i < __r1; i++) { value = obj[i]; }",
      "for value, i of obj; end"
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
    assert_format "function a() { y; return z; }", "def a; y; z; end"
    assert_format "function a(b, c, d) {}", "def a(b, c, d) end"

    assert_format "a.b.c.d = function () {};", "def a.b.c.d; end"
    assert_format "a[x] = function () {};", "def a[x]; end"
    assert_format "a[0].z = function () {};", "def a[0].z; end"
  end

  def test_argument_splats_in_function_statements
    assert_format "function a() { var b = Array.prototype.slice.call(arguments); }",
      "def a(*b) end"

    assert_format "function a(b, c) { var d = Array.prototype.slice.call(arguments, 2); }",
      "def a(b, c, *d) end"

    assert_format "function a(b) { var d = Array.prototype.slice.call(arguments, 1, -1); var e = arguments[arguments.length - 1]; }",
      "def a(b, *d, e) end"
  end

  def test_default_argument_in_function_statements
    assert_format "function x(a) { if (a === undefined) a = 'b'; return log(a); }",
      "def x(a = 'b') log(a); end"

    assert_format "function x(a) { if (a === undefined) a = 'b'; }",
      "def x(a = 'b') end"

    assert_format "function x(a, b, c) { if (c === undefined) c = 2; }",
      "def x(a, b, c = 2) end"

    assert_format "function x(a, b, c, d) { if (c === undefined) c = 2; if (d === undefined) d = 3; }",
      "def x(a, b, c = 2, d = 3) end"
  end

  def test_variable_scoping_in_function_statements
    assert_format "function x() { var a, b; b = 1; return a = 2; }",
      "def x() b = 1; a = 2; end"

    assert_format "function x(a, b) { var c; a += 1; b = 2; return c = 3; }",
      "def x(a, b) a += 1; b = 2; c = 3; end"

    assert_format "function x(a) { var c; a = {}; a.b = 2; return c = 3; }",
      "def x(a) a = {}; a.b = 2; c = 3; end"

    assert_format "function x(b) { var a = Array.prototype.slice.call(arguments, 1); var c; c = b; b = a; return a = {}; }",
      "def x(b, *a) c = b; b = a; a = {}; end"
  end

  def test_variable_scoping_in_program
    assert_format "var a, b, c; a = b = c = 1;", "a = b = c = 1"
    assert_format "var a; a = {}; a.b = 1;", "a = {}; a.b = 1"
  end

  def test_class_statement
    assert_format "function A() {}", "class A; end"

    assert_format(/function Post\(\) { Some\.Extern\.Model\.apply\(this, arguments\); } Post\.prototype = Object\.create\(Some\.Extern\.Model\.prototype, .+\);/,
      "class Post < Some\.Extern\.Model; end")

    assert_format "function A() {} A.prototype.name = 'class A'; A.prototype.prop = 123;",
      "class A; name = 'class A'; prop = 123; end"

    assert_format "function A() {} A.prototype.add = function (a, b) { return a + b; };",
      "class A; def add(a, b); return a + b; end; end"
  end

  def test_class_constructors
    assert_format(/function A\(\) { B\.apply\(this, arguments\); } A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; end")

    assert_format(/function A\(\) {} A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; def constructor; end end")
  end

  def test_object_statement
    assert_format "var A = Object.create(Object);", "object A; end"
    assert_format "var A = Object.create(B);", "object A < B; end"
    assert_format "var Post = Object.create(Some.Extern.Model);", "object Post < Some.Extern.Model; end"

    assert_format "var A = Object.create(Object); A.name = 'object A'; A.prop = 123;",
      "object A; name = 'object A'; prop = 123; end"

    assert_format "var A = Object.create(Object); A.add = function (a, b) { return a + b; };",
      "object A; def add(a, b); return a + b; end; end"
  end

  def test_nested_object_and_class_statements
    assert_format "var A = Object.create(Object); A.B = Object.create(Object);",
      "object A; object B; end; end"

    assert_format "var A = Object.create(Object); A.foo = 'bar'; A.baz = function () { return this.foo; };",
      "object A; foo = 'bar'; def baz; return this.foo; end; end;"

    assert_format "var A = Object.create(Object); A.B = Object.create(Object); A.B.foo = 'bar'; A.B.baz = function () { return this.foo; };",
      "object A; object B; foo = 'bar'; def baz; return this.foo; end; end; end"

    assert_format "var A = Object.create(Object); A.B = function () {}; A.B.prototype.foo = 'bar'; A.B.prototype.baz = function () { return this.foo; };",
      "object A; class B; foo = 'bar'; def baz; return this.foo; end; end; end"

    assert_format "function A() {} A.B = Object.create(Object); A.B.foo = 'bar'; A.B.baz = function () { return this.foo; };",
      "class A; object B; foo = 'bar'; def baz; return this.foo; end; end; end"
  end

  def test_super_in_class_constructors
    assert_format(/function A\(\) { B\.apply\(this, arguments\); } A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; def constructor; super; end end")

    assert_format(/function A\(\) { B\.call\(this\); } A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; def constructor; super(); end end")

    assert_format(/function A\(\) { B\.call\(this, a, 2\); } A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; def constructor; super(a, 2); end end")

    assert_format(/function A\(\) { B\.apply\(this, args\); } A\.prototype = Object\.create\(B\.prototype, .+\);/,
      "class A < B; def constructor; super(*args); end end")
  end

  def test_super_in_class_methods
    assert_format(/A\.prototype\.bar = function \(\) { return B\.prototype\.bar\.apply\(this, arguments\); };/,
      "class A < B; def bar; super; end end")

    assert_format(/A\.prototype\.foo = function \(\) { return B\.prototype\.foo\.call\(this\); };/,
      "class A < B; def foo; super(); end end")

    assert_format(/A\.prototype\.baz = function \(a\) { return B\.prototype\.baz\.call\(this, a, 2\); };/,
      "class A < B; def baz(a); super(a, 2); end end")

    assert_format(/A\.prototype\.foo = function \(\) { return B\.prototype\.foo\.apply\(this, *args\); };/,
      "class A < B; def foo; super(*args); end end")
  end

  def test_super_in_object_methods
    assert_format(/A.bar = function \(\) { return B\.bar\.apply\(this, arguments\); };/,
      "object A < B; def bar; super; end end")

    assert_format(/A.foo = function \(\) { return B\.foo\.call\(this\); };/,
      "object A < B; def foo; super(); end end")

    assert_format(/A.baz = function \(a\) { return B\.baz\.call\(this, a, 2\); };/,
      "object A < B; def baz(a); super(a, 2); end end")

    assert_format(/A.foo = function \(\) { return B\.foo\.apply\(this, *args\); };/,
      "object A < B; def foo; super(*args); end end")
  end

  def test_self_in_functions_and_object_and_class_methods
    assert_format(/function set\(k, v\) { return self\.attrs\[k\] = v; }/, "def set(k, v); self.attrs[k] = v; end")
    assert_format(/function \(k\) { return k\.self; }/, "object Post; def set(k); return k.self; end; end")

    assert_format(/function \(\) { var self = this; return self; }/,
      "object Post; def get(); return self; end; end")

    assert_format(/function \(\) { var self = this, x; return x = self; }/,
      "object Post; def get(); x = self; end; end")

    assert_format(/function \(k, v\) { var self = this; return self\.attrs\[k\] = v; }/,
      "object Post; def set(k, v); self.attrs[k] = v; end; end")

    assert_format(/function \(k, v\) { var self = this; return self\.attrs\[k\] = v; }/,
      "class Post; def set(k, v); self.attrs[k] = v; end; end")

    assert_format(/function \(\) { var self = this; return function \(\) { return self; }; }/,
      "class Post; def lmbd(); -> { self }; end; end")
  end

  def test_parse_new_expression
    assert_format "new Foo();", "new Foo()"
    assert_format "new Foo.Bar(a, b);", "new Foo.Bar(a, b)"
    assert_format "new Foo[bar]({ a: 1, b: 2 });", "new Foo[bar](a: 1, b: 2)"
    assert_match "(Foo, args, function () {})", format("new Foo(*args)")
    assert_match "(Foo.Bar, [].concat(a, [b, c], d), function () {})", format("new Foo.Bar(*a, b, c, *d)")
  end
end
