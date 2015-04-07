module RBS
  class Formatter
    attr_reader :parser

    def initialize(parser)
      @parser = parser
      @scopes = []
    end

    def compile(type: "iife")
      program, vars = with_scope(traversable: false) do
        compile_statements(@parser.parse.body)
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

    def compile_statements(block)
      block.map(&method(:compile_statement)).join("\n")
    end

    def compile_statement(stmt)
      case stmt.type
      when :block_statement      then compile_block_statement(stmt)
      when :expression_statement then compile_expression(stmt.expression) + ";"
      when :if_statement         then compile_if_statement(stmt)
      when :unless_statement     then compile_unless_statement(stmt)
      when :case_statement       then compile_case_statement(stmt)
      when :while_statement      then compile_while_statement(stmt)
      when :until_statement      then compile_until_statement(stmt)
      when :loop_statement       then compile_loop_statement(stmt)
      when :try_statement        then compile_try_statement(stmt)
      when :function_statement   then compile_function_statement(stmt)
      when :object_statement     then compile_object_statement(stmt)
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
      if node.body.empty? || node.body.all? { |s| s === :empty_statement }
        "{}"
      else
        "{\n#{compile_statements(node.body)}\n}"
      end
    end

    def compile_if_statement(node)
      test = compile_expression(ungroup_expression(node.test))
      body = compile_statement(node.consequent)

      if node.alternate
        alternate = compile_statement(node.alternate)
        "if (#{test}) #{body} else #{alternate}"
      else
        "if (#{test}) #{body}"
      end
    end

    def compile_unless_statement(node)
      test = compile_expression(ungroup_expression(negate(node.test)))
      body = compile_statement(node.consequent)
      "if (#{test}) #{body}"
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

    def compile_until_statement(node)
      test = compile_expression(ungroup_expression(negate(node.test)))
      body = compile_statement(node.consequent)
      "while (#{test}) #{body}"
    end

    def compile_loop_statement(node)
      body = compile_statement(node.consequent)
      "while (1) #{body}"
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
        body = body.empty? ? "{}" : "{\n#{body}\n}"
        "if (#{test}) #{body} else {\nthrow #{exception};\n}"
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
      id = if parent
             Node.new(:member_expression, object: parent, property: node.id, computed: false)
           else
             node.id
           end
      name = compile_expression(id)

      splats, args, defaults = compile_function_arguments(node)
      body, vars = with_scope(traversable: false) do
        compile_statements(node.block.body)
      end
      vars -= node.arguments.map { |arg| arg.name rescue arg.expression.name }

      body = [splats, defaults, compile_vars(vars).chomp, body].reject(&:empty?).join("\n")
      body = body.empty? ? "{}" : "{\n#{body}\n}"

      if id === :identifier
        "function #{name}(#{args.join(', ')}) #{body}"
      else
        "#{name} = function (#{args.join(', ')}) #{body};"
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
    # TODO: assign self = this in object methods (when needed)
    def compile_object_statement(node, parent: nil)
      id = if parent
             Node.new(:member_expression, object: parent, property: node.id, computed: false)
           else
             node.id
           end

      name = compile_expression(id)
      parent = node.parent ? compile_expression(node.parent) : "Object"

      body = node.body.map do |stmt|
        case stmt.type
        when :object_statement
          compile_object_statement(stmt, parent: id)
        when :function_statement
          compile_function_statement(stmt, parent: id)
        when :property
          "#{name}.#{compile_expression(stmt.key)} = #{compile_expression(stmt.value)};"
        else
          raise "unsupported object body statement"
        end
      end

      if id === :identifier
        "var #{name} = Object.create(#{parent});\n#{body.join("\n")}"
      else
        "#{name} = Object.create(#{parent});\n#{body.join("\n")}"
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
      when :identifier            then expr.name
      when :literal               then expr.value
      when :lambda_expression     then compile_lambda_expression(expr)
      when :group_expression      then compile_group_expression(expr)
      when :array_expression      then compile_array_expression(expr)
      when :object_expression     then compile_object_expression(expr)
      when :member_expression     then compile_member_expression(expr)
      when :call_expression       then compile_call_expression(expr)
      when :unary_expression      then compile_unary_expression(expr)
      when :binary_expression     then compile_binary_expression(expr)
      when :assignment_expression then compile_assignment_expression(expr)
      when :new_expression        then compile_new_expression(expr)
      else
        raise "unsupported expression: #{expr.type}"
      end
    end

    def compile_lambda_expression(node, parent: nil)
      splats, args, defaults = compile_function_arguments(node)
      body, vars = with_scope(traversable: true) do
        compile_statements(node.block.body)
      end
      vars -= node.arguments.map { |arg| arg.name rescue arg.expression.name }

      body = [splats, defaults, compile_vars(vars).chomp, body].reject(&:empty?).join("\n")
      body = body.empty? ? "{}" : "{\n#{body}\n}"

      "function (#{args.join(', ')}) #{body}"
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
      object, property = compile_expression(node.object), compile_expression(node.property)
      if node.computed
        "#{object}[#{property}]"
      else
        "#{object}.#{property}"
      end
    end

    def compile_call_expression(node)
      callee = compile_expression(node.callee)

      case args = compile_call_arguments(node)
      when String
        "#{callee}.apply(null, #{args})"
      when Array
        "#{callee}(#{args.join(', ')})"
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

    def compile_assignment_expression(node)
      declare_scope_variable(node.left.name) if node.left === :identifier
      [compile_expression(node.left), node.operator, compile_expression(node.right)].join(" ")
    end

    private

    def ungroup_expression(node)
      node === :group_expression ? node.expression : node
    end

    def negation?(node)
      node === :unary_expression && node.operator == "!"
    end

    # TODO: negate logical/binary expressions (when parser differenties & applies precedence)
    def negate(node)
      if negation?(node)
        #if node.argument === :logical_expression
        #  negate_logical_expression(node.argument)
        #elsif node.argument === :binary_expression
        #  negate_binary_expression(node.argument)
        #else
          node.argument
        #end
      #elsif node === :logical_expression
      #  negate_logical_expression(node)
      #elsif node === :binary_expression
      #  negate_binary_expression(node)
      elsif node === %i(identifier literal group_expression)
        Node.new(:unary_expression, operator: "!", argument: node)
      else
        Node.new(:unary_expression, operator: "!", argument: Node.new(:group_expression, expression: node))
      end
    end

    #def negate_logical_expression(node)
    #  left = if negation?(node.left)
    #           node.left.argument
    #         else
    #           Node.new(:unary_expression, operator: "!", argument: node.left)
    #         end
    #  right = if node.right === %i(binary_expression logical_expression) || negation?(node.right)
    #            negate(node.right)
    #          else
    #           Node.new(:unary_expression, operator: "!", argument: node.right)
    #          end
    #  operator = node.operator == "&&" ? "||" : "&&"
    #  Node.new(:logical_expression, operator: operator, left: left, right: right)
    #end

    #def negate_binary_expression(node)
    #  right = if node.right === :logical_expression
    #            negate_logical_expression(node.right)
    #          elsif node.right === :binary_expression
    #            negate_binary_expression(node.right)
    #          else
    #            node.right
    #          end
    #  operator = case node.operator
    #             when "==" then "!="
    #             when "!=" then "=="
    #             when ">=" then "<"
    #             when "<=" then ">"
    #             when ">"  then "<="
    #             when "<"  then ">="
    #             end
    #  Node.new(:binary_expression, operator: operator, left: node.left, right: right)
    #end

    def with_scope(traversable:)
      @scopes << { vars: [], traversable: traversable }
      [yield, @scopes.pop[:vars]]
    end

    def declare_scope_variable(name)
      @scopes.reverse_each do |scope|
        return if scope[:vars].include?(name)
        break unless scope[:traversable]
      end
      @scopes.last[:vars] << name
    end
  end
end
