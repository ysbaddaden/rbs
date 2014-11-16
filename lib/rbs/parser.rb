require 'rbs/errors'
require 'rbs/parser/node'

module RBS
  LHS = %i(identifier member_expression)
  INLINE_TERM = %i(EOF else elsif end when)

  # The parser is heavily influenced by Esprima's parser:
  # http://esprima.org/
  class Parser
    attr_reader :lexer

    def initialize(lexer)
      @lexer = lexer
      @index = -1
    end

    def parse
      @program ||= parse_program
    end

    def parse_program
      node(:program, body: parse_statements)
    end

    def parse_statements
      statements = []

      loop do
        break if match %i(end else elsif when)
        break unless statement = parse_statement
        statements << statement
      end

      statements
    end

    def parse_statement
      case lookahead.name
      when :EOF
        nil
      when :LF
        expect(:LF); node(:empty_statement)
      when :prototype, :def, :object, :if, :unless, :case, :while, :until, :loop, :case, :for, :return, :delete, :throw, :begin
        __send__("parse_#{lookahead.name}_statement")
      when :break, :next
        node("#{lex.name}_statement")
      else
        parse_expression_statement
      end
    end

    def parse_if_statement(recursive: false)
      expect(:if, :elsif)
      test = parse_expression
      expect(:LF, :then)

      block = node(:block_statement, body: parse_statements)

      if match(:else)
        expect(:else)
        alternate = node(:block_statement, body: parse_statements)
      elsif match(:elsif)
        alternate = parse_if_statement(recursive: true)
      end

      expect(:end) unless recursive
      expect_terminator

      node(:if_statement, test: test, consequent: block, alternate: alternate)
    end

    def parse_unless_statement
      parse_conditional(:unless, :then)
    end

    def parse_while_statement
      parse_conditional(:while, :do)
    end

    def parse_until_statement
      parse_conditional(:until, :do)
    end

    def parse_loop_statement
      expect(:loop)
      expect(:LF, :do)

      block = node(:block_statement, body: parse_statements)
      expect(:end)
      expect_terminator

      node(:loop_statement, consequent: block)
    end

    def parse_conditional(name, action)
      expect(name)
      test = parse_expression
      expect(:LF, action)

      block = node(:block_statement, body: parse_statements)
      expect(:end)
      expect_terminator

      node("#{name}_statement", test: test, consequent: block)
    end

    def parse_case_statement
      expect(:case)
      test = parse_expression
      expect(:LF) if match(:LF)

      cases = []
      loop do
        cases << parse_when_expression
        break if match(:end)
      end

      expect(:end)
      expect_terminator

      node(:case_statement, test: test, cases: cases)
    end

    def parse_when_expression
      expect(:when)
      tests = []

      loop do
        tests << parse_expression
        break if match %i(when end)
        break unless expect(',', :LF, :then) === ','
      end

      block = node(:block_statement, body: parse_statements) unless match %i(when end)
      node(:when_statement, tests: tests, consequent: block)
    end

    def parse_return_statement
      expect(:return)
      argument = parse_expression unless match(:LF) || match(INLINE_TERM)
      expect_terminator
      node(:return_statement, argument: argument)
    end

    def parse_delete_statement
      expect(:delete)
      argument = node(:identifier, name: expect(:identifier).value)
      expect_terminator
      node(:delete_statement, argument: argument)
    end

    # TODO: parse for statement modifier
    def parse_expression_statement
      expr = parse_expression

      if match %i(if unless while until)
        token = expect(:if, :unless, :while, :until)
        block = node(:block_statement, body: [expr])
        stmt = node("#{token.name}_statement", test: parse_expression, consequent: block)
      else
        stmt = node(:expression_statement, expression: expr)
      end

      expect_terminator
      stmt
    end

    def parse_expression
      left = parse_binary_expression

      if match(ASSIGNMENT_OPERATOR)
        raise ParseError, "Invalid left-hand side in assignment" unless valid_lhs?(left)
        node(:assignment_expression, operator: lex.value, left: left, right: parse_expression)
      else
        left
      end
    end

    def parse_binary_expression
      left = parse_unary_expression

      if match(BINARY_OPERATOR)
        node(:binary_expression, operator: lex.value, left: left, right: parse_expression)
      else
        left
      end
    end

    def parse_unary_expression
      if match(UNARY_OPERATOR)
        node(:unary_expression, operator: lex.value, argument: parse_expression)
      else
        parse_member_expression
      end
    end

    def parse_member_expression
      expr = parse_primary_expression

      loop do
        if match('.')
          expect('.')
          property = node(:identifier, name: expect(:identifier).value)
          expr = node(:member_expression, computed: false, object: expr, property: property)
        elsif match('[')
          expect('[')
          expr = node(:member_expression, computed: true, object: expr, property: parse_expression)
          expect(']')
        elsif match('(')
          arguments = parse_list '(', ')', :parse_call_argument
          expr = node(:call_expression, callee: expr, arguments: arguments)
        else
          break
        end
      end

      expr
    end

    def parse_call_argument
      if match('*')
        expect('*')
        node(:splat_expression, expression: parse_expression)
      else
        if lookahead(1) === :identifier && lookahead(2) === ':'
          parse_object_argument
        else
          parse_expression
        end
      end
    end

    def parse_object_argument
      properties = []

      loop do
        properties << parse_object_property
        expect(',') if match(',')
        break if match(')')
      end

      node(:object_expression, properties: properties)
    end

    def parse_primary_expression
      case lookahead.name
      when :BOOLEAN, :NIL, :NUMBER, :REGEXP
                       then node(:literal, value: lex.value)
      when :STRING     then node(:literal, value: "'%s'" % lex.value)
      when :identifier then node(:identifier, name: lex.value)
      when :'['        then parse_array
      when :'{'        then parse_object
      when :'->'
      else             unexpected_error(lex)
      end
    end

    def parse_array
      elements = parse_list('[', ']', :parse_expression)
      node(:array_expression, elements: elements)
    end

    def parse_object
      properties = parse_list('{', '}', :parse_object_property)
      node(:object_expression, properties: properties)
    end

    def parse_object_property
      token = expect(:identifier, :STRING)
      key = case token.name
            when :identifier then node(:identifier, name: token.value)
            when :STRING     then node(:literal, value: "'%s'" % token.value)
            end
      expect(':')
      value = parse_expression
      node(:property, key: key, value: value)
    end

    def parse_list(before, after, method)
      list = []
      expect(before) if before

      if match(after)
        expect(after)
        return list
      end

      loop do
        list << __send__(method)
        token = expect(',', after)

        break if token === after
        lex and break if lookahead === after
      end

      list
    end

    private

    def node(type_or_token, params = nil)
      if type_or_token.is_a?(RBS::Token)
        Node.new(type_or_token.name, value: type_or_token.value)
      else
        Node.new(type_or_token, params)
      end
    end

    def expect(*types)
      lex.tap do |token|
        unexpected_error(token, *types.flatten) unless token === types.flatten
      end
    end

    def expect_terminator
      expect(:LF) unless match(INLINE_TERM)
    end

    def unexpected_error(token, *expected)
      message = case expected.size
                when 0
                  "Unexpected token #{token.name} at #{token.position}"
                when 1
                  "Unexpected token #{token.name} at #{token.position}, expected #{expected.first}"
                else
                  tokens = expected.map { |t| t.is_a?(String) ? "'#{t}'" : t }
                  tokens.pop.tap { |t| tokens[tokens.size - 1] = "#{tokens.last} or #{t}" } if tokens.size > 1
                  "Unexpected token #{token.name} at #{token.position}, expected one of #{tokens.join(', ')}"
                end
      raise ParseError.new(message, token: token)
    end

    def match(type)
      lookahead === type
    end

    def lex
      @index += 1
      lexer.tokens[@index] or unexpected_error(:EOF)
    end

    def lookahead(peek = 1)
      lexer.tokens[@index + peek]
    end

    def valid_lhs?(left)
      left.type == :member_expression || (
        left.type == :identifier && left.name != 'this' && left.name != 'self'
      )
    end
  end
end
