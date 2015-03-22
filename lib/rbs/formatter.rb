module RBS
  class Formatter
    attr_reader :parser

    def initialize(parser)
      @parser = parser
    end

    def compile(raw: false)
      "".tap do |code|
        code << "(function () {\n'use strict';" unless raw
        code << compile_statements(@parser.parse.body)
        code << "\n}());" unless raw
      end
    end

    def compile_statements(block)
      block.map(&method(:compile_statement)).join("\n")
    end

    # TODO: if_statement
    # TODO: unless_statement
    # TODO: case_statement
    # TODO: while_statement
    # TODO: until_statement
    # TODO: loop_statement
    # TODO: def_statement
    # TODO: begin_statement
    # TODO: object_statement
    def compile_statement(stmt)
      case stmt.type
      when :expression_statement then compile_expression(stmt.expression) + ";"
      when :return_statement     then compile_return_statement(stmt)
      when :delete_statement     then "delete #{compile_expression(stmt.argument)};"
      when :next_statement       then "next;"
      when :break_statement      then "break;"
      when :empty_statement      then # skip
      else
        raise "unsupported statement: #{stmt.type}"
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
      when :group_expression      then compile_group_expression(expr)
      when :array_expression      then compile_array_expression(expr)
      when :object_expression     then compile_object_expression(expr)
      when :member_expression     then compile_member_expression(expr)
      when :call_expression       then compile_call_expression(expr)
      when :splat_expression      then compile_splat_expression(expr)
      when :unary_expression      then compile_unary_expression(expr)
      when :binary_expression     then compile_binary_expression(expr)
      when :assignment_expression then compile_assignment_expression(expr)
      else
        raise "unsupported expression: #{expr.type}"
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

    # TODO: object argument
    def compile_call_expression(node)
      callee = compile_expression(node.callee)

      if node.arguments.size == 0
        return "#{callee}()"
      end

      if node.arguments.all? { |a| a === :splat_expression }
        arg = if node.arguments.size == 1
                compile_expression(node.arguments[0].expression)
              else
                one = compile_expression(node.arguments[0].expression)
                more = node.arguments.slice(1 .. -1).map { |a| compile_expression(a.expression) }
                "#{one}.concat(#{more.join(', ')})"
              end
        return "#{callee}.apply(null, #{arg})"
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

        return "#{callee}.apply(null, #{args.shift}.concat(#{args.join(', ')}))"
      end

      args = node.arguments.map(&method(:compile_expression))
      "#{callee}(#{args.join(', ')})"
    end

    def compile_unary_expression(node)
      separator = node.operator =~ /[a-z]+/ ? " " : ""
      [node.operator, compile_expression(node.argument)].join(separator)
    end

    def compile_binary_expression(node)
      [compile_expression(node.left), node.operator, compile_expression(node.right)].join(" ")
    end

    def compile_assignment_expression(node)
      [compile_expression(node.left), node.operator, compile_expression(node.right)].join(" ")
    end
  end
end
