module RBS
  class Formatter
    attr_reader :parser

    def initialize(parser)
      @parser = parser
      @scopes = []
      @functions = []
      @objects = []
      @reference = 0
    end

    def compile(type: "iife", experimental: false)
      program, vars = with_scope(traversable: false) do
        compile_statements(@parser.parse(experimental: experimental).body)
      end
      code = compile_vars(vars) + program

      case type
      when "amd"
        "define(function (require, exports, module) {\n'use strict';\n\n#{code}\n});"
      when "iife"
        "(function () {\n'use strict';\n\n#{code}\n}());"
      when "raw"
        code
      else
        raise ArgumentError, "unknown module type: '#{type}'"
      end
    end

    def compile_statements(stmts)
      stmts.map(&method(:compile_statement)).join("\n")
    end

    def compile_statement(stmt)
      case stmt.type
      when :block_statement      then compile_block_statement(stmt)
      when :expression_statement then compile_expression(stmt.expression) + ";"
      when :if_statement         then compile_if_statement(stmt)
      when :case_statement       then compile_case_statement(stmt)
      when :while_statement      then compile_while_statement(stmt)
      when :for_in_statement     then compile_for_in_statement(stmt)
      when :for_of_statement     then compile_for_of_statement(stmt)
      when :loop_statement       then compile_loop_statement(stmt)
      when :try_statement        then compile_try_statement(stmt)
      when :function_statement   then compile_function_statement(stmt)
      when :object_statement     then compile_object_statement(stmt)
      when :class_statement      then compile_class_statement(stmt)
      when :return_statement     then compile_return_statement(stmt)
      when :delete_statement     then "delete #{compile_expression(stmt.argument)};"
      when :next_statement       then "continue;"
      when :break_statement      then "break;"
      when :empty_statement      then # skip
      else
        raise "unsupported statement: #{stmt.type}"
      end
    end

    def compile_block_statement(node)
      stmts = node.body.reject { |s| s === :empty_statement }
      block compile_statements(stmts)
    end

    def compile_if_statement(node)
      test = compile_expression(ungroup_expression(node.test))
      body = compile_statement(node.consequent)

      if node.respond_to?(:alternate) && node.alternate
        alternate = compile_statement(node.alternate)
        "if (#{test}) #{body} else #{alternate}"
      else
        "if (#{test}) #{body}"
      end
    end

    def compile_case_statement(node)
      test = compile_expression(ungroup_expression(node.test))

      body = node.cases.map do |case_|
        tests = case_.tests.map { |t| "case " + compile_expression(t) + ":" }.join("\n")

        if case_.consequent
          block = compile_statements(case_.consequent.body)
          if case_.consequent.body.last === :return_statement
            "#{tests}\n#{block}"
          else
            "#{tests}\n#{block}\nbreak;"
          end
        else
          "#{tests}\nbreak;"
        end
      end

      if node.alternate
        body << "default:\n" + compile_statements(node.alternate.body)
      end

      "switch (#{test}) {\n#{body.join("\n")}\n}"
    end

    def compile_while_statement(node)
      test = compile_expression(ungroup_expression(node.test))
      body = compile_statement(node.consequent)
      "while (#{test}) #{body}"
    end

    def compile_loop_statement(node)
      body = compile_statement(node.consequent)
      "while (1) #{body}"
    end

    # TODO: temporary reference for object (when looping with value for quicker access)
    def compile_for_in_statement(node)
      declare_scope_variable key = compile_expression(node.key)
      object = compile_expression(node.object)
      body = compile_statement(node.block)

      if node.value
        declare_scope_variable value = compile_expression(node.value)
        body = "{\n" + value + " = #{object}[#{key}];\n" + body.slice(1 .. -1)
      end

      "for (#{key} in #{object}) #{body}"
    end

    # TODO: temporary reference for collection (unless it's simple enough)
    def compile_for_of_statement(node)
      declare_scope_variable value = compile_expression(node.value)
      collection = compile_expression(node.collection)
      body = compile_statement(node.block)

      if node.index
        declare_scope_variable index = compile_expression(node.index)
      else
        index = generate_reference
      end

      len = generate_reference

      body = "{\n" + value + " = #{collection}[#{index}];\n" + body.slice(1 .. -1)
      "for (#{index} = 0, #{len} = #{collection}.length; #{index} < #{len}; #{index}++) #{body}"
    end

    def compile_try_statement(node)
      exception = "__rbs_exception"
      exceptions = nil
      body = compile_statement(node.block)
      finalizer = "\nfinally #{compile_statement(node.finalizer)}" if node.finalizer

      if node.handlers.empty? && node.finalizer
        return "try #{body}#{finalizer}"
      end

      handlers = case node.handlers.size
                 when 0
                   "throw #{exception};" unless node.finalizer
                 when 1
                   handler = node.handlers.first
                   exception = handler.param.name if handler.param
                   compile_catch_clause(handler, exception)
                 else
                   params = node.handlers.map(&:param).uniq { |param| param && param.name }.compact
                   case params.size
                   when 0 then # skip
                   when 1 then exception = params.first.name
                   else        exceptions = "var " + params.map(&:name).join(", ") + ";\n"
                   end
                   compile_catch_clauses(node.handlers, exception)
                 end

      handlers = if handlers.nil?
                   nil
                 elsif handlers.empty?
                   "{}"
                 else
                   "{\n#{exceptions}#{handlers}\n}"
                 end

      "try #{body} catch (#{exception}) #{handlers}#{finalizer}"
    end

    def compile_catch_clause(handler, exception)
      body = if handler.body.any?
                compile_statements(handler.body)
              else
                ""
              end

      if handler.class_names.any?
        test = handler.class_names
          .map { |id| "#{exception} instanceof #{id.name}" }
          .join(" || ")
        "if (#{test}) #{block body} else {\nthrow #{exception};\n}"
      else
        body
      end
    end

    def compile_catch_clauses(handlers, exception)
      conditions = handlers.map do |handler|
        ex = if handler.param && handler.param.name != exception
               "#{handler.param.name} = #{exception};\n"
             else
               ""
             end

        body = if handler.body.any?
                 "{\n" + ex + compile_statements(handler.body) + "\n}"
               else
                 "{}"
               end

        if handler.class_names.any?
          test = handler.class_names.map { |id| "#{exception} instanceof #{id.name}" }.join(" || ")
          "if (#{test}) #{body}"
        else
          body
        end
      end

      if handlers.any? { |handler| handler.class_names.empty? }
        conditions.join(" else ")
      else
        conditions.join(" else ") + " else {\nthrow #{exception};\n}"
      end
    end

    def compile_function_statement(node, parent: nil)
      args, body = compile_function_body(node, may_have_self: !!parent)

      if node.id === :identifier && !parent
        "function #{node.id.name}(#{args.join(', ')}) #{block body}"
      else
        parent = compile_expression(parent) + "." if parent
        name = parent.to_s + compile_expression(node.id)
        "#{name} = function (#{args.join(', ')}) #{block body};"
      end
    end

    def compile_function_body(node, may_have_self: false)
      with_function(node.id) do
        splats, args, defaults = compile_function_arguments(node)

        body, vars = with_scope(traversable: false, may_have_self: may_have_self) do
          compile_statements(node.block.body)
        end

        vars -= node.arguments.map do |arg|
          arg.respond_to?(:name) ? arg.name : arg.expression.name
        end

        body = [splats, defaults, compile_vars(vars).chomp, body].reject(&:empty?).join("\n")
        [args, body]
      end
    end

    def compile_vars(vars)
      if vars.any?
        "var " + vars.sort.join(", ") + ";\n"
      else
        ""
      end
    end

    def compile_function_arguments(node)
      splats, args, defaults = [], [], []

      node.arguments.each_with_index do |arg, index|
        if arg === :splat_expression
          splats << if index == 0 && node.arguments.size == 1
                      "var #{compile_expression(arg.expression)} = Array.prototype.slice.call(arguments);"
                    elsif index == node.arguments.size - 1
                      "var #{compile_expression(arg.expression)} = Array.prototype.slice.call(arguments, #{index});"
                    else
                      len = index - node.arguments.size + 1
                      "var #{compile_expression(arg.expression)} = Array.prototype.slice.call(arguments, #{index}, #{len});"
                    end
        else
          if splats.any?
            splats << "var #{compile_expression(arg)} = arguments[arguments.length - #{node.arguments.size - index}];"
          else
            args << compile_expression(arg)
          end

          if arg.default
            arg_name = compile_expression(arg)
            default_value = compile_expression(arg.default)
            defaults << "if (#{arg_name} === undefined) #{arg_name} = #{default_value};"
          end
        end
      end

      [splats, args, defaults]
    end

    # TODO: reopening object statements (ie. verify the object doesn't exist, yet)
    def compile_object_statement(node, parent: nil)
      id = if parent
             Node.new(:member_expression, object: parent, property: node.id, computed: false)
           else
             node.id
           end

      name = compile_expression(id)
      parent = node.parent ? compile_expression(node.parent) : "Object"

      with_object(:object, name, parent) do
        body = compile_object_body(:object, id, name, node)

        if id === :identifier
          "var #{name} = Object.create(#{parent});\n#{body}"
        else
          "#{name} = Object.create(#{parent});\n#{body}"
        end
      end
    end

    def compile_object_body(type, id, name, node)
      obj = if type == :class
              Node.new(:member_expression, object: id, property: Node.new(:identifier, name: "prototype"), computed: false)
            else
              id
            end

      body = node.body.map do |stmt|
        case stmt.type
        when :object_statement
          compile_object_statement(stmt, parent: id)
        when :class_statement
          compile_class_statement(stmt, parent: id)
        when :function_statement
          compile_function_statement(stmt, parent: obj)
        when :property
          key = if type == :class
                  "#{name}.prototype.#{compile_expression(stmt.key)}"
                else
                  "#{name}.#{compile_expression(stmt.key)}"
                end
          "#{key} = #{compile_expression(stmt.value)};"
        else
          raise "unsupported object body statement"
        end
      end

      body.empty? ? "" : body.join("\n") + "\n"
    end

    # TODO: reopening class statements (ie. verify the class doesn't exist, yet)
    def compile_class_statement(node, parent: nil)
      id = if parent
             Node.new(:member_expression, object: parent, property: node.id, computed: false)
           else
             node.id
           end
      name = compile_expression(id)
      parent = compile_expression(node.parent) if node.parent

      with_object(:class, name, parent) do
        definition = compile_class_constructor(id, name, node)
        definition += "\n#{name}.prototype = Object.create(#{parent}.prototype, {\n" <<
                        "constructor: { value: #{name}, enumerable: false, writable: true, configurable: true }\n" <<
                      "});" if node.parent
        definition + "\n" + compile_object_body(:class, id, name, node)
      end
    end

    def compile_class_constructor(id, name, node)
      # TODO: class constructor should be determined at the parser/rewriter level
      index = node.body.find_index do |stmt|
        stmt === :function_statement && stmt.id === :identifier && stmt.id.name == "constructor"
      end
      stmt = node.body.delete_at(index) if index

      args = []
      body = if node.parent === :identifier && node.parent.name == "Error"
               "var tmp = Error.apply(this, arguments);\n" <<
               "Object.getOwnPropertyNames(tmp).forEach(function (propName) {\n" <<
               "Object.defineProperty(this, propName, Object.getOwnPropertyDescriptor(tmp, propName));\n" <<
               "}, this);\n" <<
               "this.name = '#{name}';"
             end

      if stmt
        args, tmp = compile_function_body(stmt, may_have_self: true)
        body = body ? body + "\n" + tmp : tmp
      elsif node.parent && body.nil?
        body = "#{compile_expression(node.parent)}.apply(this, arguments);"
      end

      if id === :identifier
        "function #{name}(#{args.join(', ')}) #{block body}"
      else
        "#{name} = function (#{args.join(', ')}) #{block body};"
      end
    end

    def compile_return_statement(node)
      if node.argument
        "return #{compile_expression(node.argument)};"
      else
        "return;"
      end
    end

    def compile_expression(expr)
      case expr.type
      when :identifier             then compile_identifier(expr)
      when :literal                then expr.value
      when :lambda_expression      then compile_lambda_expression(expr)
      when :group_expression       then compile_group_expression(expr)
      when :array_expression       then compile_array_expression(expr)
      when :object_expression      then compile_object_expression(expr)
      when :member_expression      then compile_member_expression(expr)
      when :call_expression        then compile_call_expression(expr)
      when :unary_expression       then compile_unary_expression(expr)
      when :binary_expression      then compile_binary_expression(expr)
      when :conditional_expression then compile_conditional_expression(expr)
      when :assignment_expression  then compile_assignment_expression(expr)
      when :new_expression         then compile_new_expression(expr)
      else
        raise "unsupported expression: #{expr.type}"
      end
    end

    def compile_identifier(node, define_self: true)
      if node.name == "super"
        compile_super_expression(node)
      else
        declare_self_variable if define_self && node.name == "self"
        node.name.to_s
      end
    end

    # OPTIMIZE: reduce duplication with compile_function_body
    def compile_lambda_expression(node, parent: nil)
      splats, args, defaults = compile_function_arguments(node)
      body, vars = with_scope(traversable: true) do
        compile_statements(node.block.body)
      end

      vars -= node.arguments.map do |arg|
        arg.respond_to?(:name) ? arg.name : arg.expression.name
      end

      body = [splats, defaults, compile_vars(vars).chomp, body].reject(&:empty?).join("\n")
      "function (#{args.join(', ')}) #{block body}"
    end

    def compile_vars(vars)
      if vars.any?
        "var " + vars.sort.join(", ") + ";\n"
      else
        ""
      end
    end

    def compile_group_expression(node)
      "(" + compile_expression(node.expression) + ")"
    end

    def compile_array_expression(node)
      args = node.elements.map(&method(:compile_expression))
      "[" + args.join(", ") + "]"
    end

    def compile_object_expression(node)
      if node.properties.any?
        properties = node.properties.map do |property|
          [compile_expression(property.key), compile_expression(property.value)].join(": ")
        end
        "{ " + properties.join(", ") + " }"
      else
        "{}"
      end
    end

    def compile_member_expression(node)
      object = compile_expression(node.object)

      if node.computed
        "#{object}[#{compile_expression(node.property)}]"
      else
        "#{object}.#{compile_identifier(node.property, define_self: false)}"
      end
    end

    def compile_call_expression(node)
      if node.callee === :identifier && node.callee.name == "super"
        return compile_super_expression(node)
      end

      callee = compile_expression(node.callee)

      case args = compile_call_arguments(node)
      when String
        "#{callee}.apply(null, #{args})"
      when Array
        "#{callee}(#{args.join(', ')})"
      end
    end

    def compile_super_expression(node)
      obj, fn = @objects.last, @functions.last
      callee = if fn[:name] == "constructor"
                 obj[:parent]
               elsif obj[:type] == :class
                 "#{obj[:parent]}.prototype.#{fn[:name]}"
               else
                 "#{obj[:parent]}.#{fn[:name]}"
               end

      unless node.respond_to?(:arguments)
        return "#{callee}.apply(this, arguments)"
      end

      if node.arguments.empty?
        return "#{callee}.call(this)"
      end

      case args = compile_call_arguments(node)
      when String
        "#{callee}.apply(this, #{args})"
      when Array
        "#{callee}.call(this, #{args.join(', ')})"
      end
    end

    def compile_new_expression(node)
      callee = compile_expression(node.callee)

      case args = compile_call_arguments(node)
      when String
        "(function (fn, args, ctor) {" <<
        "  ctor.constructor = fn.constructor;" <<
        "  var child = new ctor(), result = fn.apply(child, args), t = typeof result;" <<
        "  return (t == 'object' || t == 'function') result || child : child;" <<
        "}(#{callee}, #{args}, function () {}))"
      when Array
        "new #{callee}(#{args.join(', ')})"
      end
    end

    def compile_call_arguments(node)
      if node.arguments.size == 0
        return []
      end

      if node.arguments.all? { |a| a === :splat_expression }
        arg = if node.arguments.size == 1
                compile_expression(node.arguments[0].expression)
              else
                splats = node.arguments.map { |a| compile_expression(a.expression) }
                "[].concat(#{splats.join(', ')})"
              end
        return arg
      end

      if node.arguments.any? { |a| a === :splat_expression }
        grp = node.arguments.reduce([]) do |a, e|
          if a.any? && e.type == a.last[0].type
            a.last << e
          else
            a << [e]
          end
          a
        end

        args = grp.map do |g|
          if g.first === :splat_expression
            g.map { |a| compile_expression(a.expression) }.join(", ")
          else
            "[" + g.map(&method(:compile_expression)).join(", ") + "]"
          end
        end

        first = args.first.start_with?("[") ? args.shift : "[]"
        return "#{first}.concat(#{args.join(', ')})"
      end

      node.arguments.map(&method(:compile_expression))
    end

    def compile_unary_expression(node)
      separator = node.operator =~ /[a-z]+/ ? " " : ""
      [node.operator, compile_expression(node.argument)].join(separator)
    end

    def compile_binary_expression(node)
      [compile_expression(node.left), node.operator, compile_expression(node.right)].join(" ")
    end

    def compile_conditional_expression(node)
      [compile_expression(node.test), "?", compile_expression(node.consequent), ":", compile_expression(node.alternate)].join(" ")
    end

    def compile_assignment_expression(node)
      declare_scope_variable(node.left.name) if node.left === :identifier
      [compile_expression(node.left), node.operator, compile_expression(node.right)].join(" ")
    end

    private

    def block(body)
      body.to_s.empty? ? "{}" : "{\n#{body}\n}"
    end

    def ungroup_expression(node)
      node === :group_expression ? node.expression : node
    end

    def with_object(type, name, parent)
      @objects << { type: type, name: name, parent: parent }
      yield
    ensure
      @objects.pop
    end

    def with_function(id)
      @functions << { name: compile_expression(id), self: false }
      yield
    ensure
      @functions.pop
    end

    def with_scope(traversable:, may_have_self: false)
      @scopes << { vars: [], traversable: traversable, may_have_self: may_have_self}
      [yield, @scopes.pop[:vars]]
    end

    def declare_scope_variable(name)
      @scopes.reverse_each do |scope|
        return if scope[:vars].include?(name)
        break unless scope[:traversable]
      end
      @scopes.last[:vars] << name
    end

    def declare_self_variable
      @scopes.reverse_each do |scope|
        if scope[:may_have_self]
          scope[:vars] << "self = this" unless scope[:vars].include?("self = this")
          break
        end
        break unless scope[:traversable]
      end
    end

    # TODO: generate nicer variables like a, b or c (depending on the availablity in the scope)
    def generate_reference
      ("__r" + (@reference += 1).to_s).tap do |ref|
        declare_scope_variable(ref)
      end
    end
  end
end
