require 'rbs/errors'
require 'rbs/parser/node'

module RBS
  LHS = %i(identifier member_expression)
  INLINE_TERM = %i(EOF else elsif end when })

  BINARY_PRECEDENCE = {
    '||'  => 1,
    '&&'  => 2,
    '|'   => 3,
    '^'   => 4,
    '&'   => 5,
    '=='  => 6,
    '!='  => 6,
    '<'   => 7,
    '>'   => 7,
    '<='  => 7,
    '>='  => 7,
   #'instanceof' => 7,
    '<<'  => 8,
    '>>'  => 8,
   #'>>>' => 8,
    '+'   => 9,
    '-'   => 9,
    '*'   => 11,
    '/'   => 11,
    '%'   => 11,
    '~'   => 12,
    '...' => 12,
    '..'  => 12,
  }

  # The parser is heavily influenced by Esprima's parser:
  # http://esprima.org/
  class Parser
    attr_reader :lexer

    def initialize(lexer)
      @lexer = lexer
      @index = -1
    end

    def parse(_ = nil)
      @program ||= parse_program
    end

    def parse_program
      node(:program, body: parse_statements)
    end

    def parse_statements
      statements = []

      loop do
        break if match %i(end else elsif when rescue ensure })
        break unless statement = parse_statement
        statements << statement
      end

      statements
    end

    # TODO: parse for statement modifier
    def parse_statement
      stmt = case lookahead.name
             when :EOF
               return nil
             when :LF
               expect(:LF)
               return node(:empty_statement)
             when :class, :object, :def, :if, :unless, :case, :while, :until, :loop, :case, :for, :return, :delete, :begin
               __send__("parse_#{lookahead.name}_statement")
             when :break, :next
               node("#{lex.name}_statement")
             else
               return parse_expression_statement
             end

      if statement_modifier?
        expect_statement_modifier(stmt)
      else
        expect_terminator if match(:LF)
        stmt
      end
    end

    def parse_for_statement
      expect(:for)
      left = node(expect(:identifier))

      if match(',')
        expect(',')
        b = node(expect(:identifier))
      end

      token = expect(:in, :of)
      right = parse_expression
      block = node(:block_statement, body: parse_statements)
      expect(:end)

      if token === :in
        node(:for_in_statement, key: left, value: b, object: right, block: block)
      else
        node(:for_of_statement, value: left, index: b, collection: right, block: block)
      end
    end

    def parse_def_statement(allow_member: true)
      expect(:def)

      id = if allow_member
             parse_member_expression(allow_calls: false)
           else
             node(expect(:identifier))
           end
      arguments = parse_def_arguments
      block = node(:block_statement, body: parse_statements)

      handlers = parse_rescue_clauses
      finalizer = parse_ensure_clause
      expect(:end)

      if handlers.any? || finalizer
        block = node(:try_statement, block: block, handlers: handlers, finalizer: finalizer)
      end

      node(:function_statement, id: id, arguments: arguments, block: block)
    end

    def parse_def_arguments
      position_token = lookahead

      if match '('
        arguments = parse_list '(', ')', &method(:parse_def_argument)
        expect(:LF) if match(:LF)
      else
        arguments = parse_list nil, :LF, &method(:parse_def_argument)
      end

      if duplicated_argument?(arguments)
        syntax_error("duplicated argument name", position_token)
      end

      arguments
    end

    # TODO: keyword arguments
    def parse_def_argument(list)
      if match('*')
        unexpected_error(lex) if list.any? { |a| a === :splat_expression }
        expect('*')
        token = expect(:identifier)
        node(:splat_expression, expression: node(token))
      else
        token = expect(:identifier)
        if match('=')
          expect('=')
          node(:identifier, name: token.value, default: parse_expression)
        else
          node(:identifier, name: token.value, default: nil)
        end
      end
    end

    def parse_object_statement
      expect(:object)
      id, parent, body = parse_object_definition
      node(:object_statement, id: id, parent: parent, body: body)
    end

    def parse_class_statement
      expect(:class)
      id, parent, body = parse_object_definition
      node(:class_statement, id: id, parent: parent, body: body)
    end

    def parse_object_definition
      id = parse_member_expression(allow_calls: false)

      if match('<')
        expect('<')
        parent = parse_member_expression(allow_calls: false)
      end

      expect(:LF)

      body = []

      loop do
        if match(:end)
          break
        elsif match(:object)
          body << parse_object_statement
          expect(:LF) if match(:LF)
          next
        elsif match(:class)
          body << parse_class_statement
          expect(:LF) if match(:LF)
          next
        elsif match(:def)
          body << parse_def_statement(allow_member: false)
        elsif lookahead === :identifier
          key = expect(:identifier)
          expect('=')
          body << node(:property, key: node(key), value: parse_expression)
        else
          unexpected_error(lex)
        end
        expect(:LF) unless match(:end)
      end

      expect(:end)

      [id, parent, body]
    end

    # TODO: begin/end without rescue/ensure should be a block_statement (ie. isolated scope)
    # TODO: else statement after exception
    def parse_begin_statement
      expect(:begin)
      expect(:LF)

      block = node(:block_statement, body: parse_statements)
      handlers = parse_rescue_clauses
      finalizer = parse_ensure_clause

      expect(:end)
      expect(:LF) if match(:LF)
      node(:try_statement, block: block, handlers: handlers, finalizer: finalizer)
    end

    def parse_rescue_clauses
      handlers = []

      loop do
        break if match %i(ensure end)
        handlers << parse_rescue_clause
      end

      handlers
    end

    def parse_rescue_clause
      expect(:rescue)
      class_names = []

      loop do
        break if match %i(=> LF)
        class_names << node(expect(:identifier))
        break if match %i(=> LF)
        expect(',')
      end

      if match('=>')
        expect('=>')
        param = node(expect(:identifier))
      end

      expect(:LF)
      node(:catch_clause, class_names: class_names, param: param, body: parse_statements)
    end

    def parse_ensure_clause
      if match(:ensure)
        expect(:ensure)
        expect(:LF) if match(:LF)
        node(:block_statement, body: parse_statements)
      end
    end

    def parse_if_statement(recursive: false)
      expect(:if, :elsif)
      test = parse_expression
      expect(:LF, :then)

      block = node(:block_statement, body: parse_statements)

      if match(:else)
        expect(:else)
        expect(:LF) if match(:LF)
        alternate = node(:block_statement, body: parse_statements)
      elsif match(:elsif)
        alternate = parse_if_statement(recursive: true)
      end

      if recursive
        expect_terminator
      else
        expect(:end)
      end

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

      node(:loop_statement, consequent: block)
    end

    def parse_conditional(name, action)
      expect(name)
      test = parse_expression
      expect(:LF, action)

      block = node(:block_statement, body: parse_statements)
      expect(:end)

      node("#{name}_statement", test: test, consequent: block)
    end

    def parse_case_statement
      expect(:case)
      test = parse_expression
      expect(:LF) if match(:LF)

      cases = []
      loop do
        cases << parse_when_expression
        break if match %i(else end)
      end

      if match(:else)
        expect(:else)
        alternate = node(:block_statement, body: parse_statements)
      end

      expect(:end)
      node(:case_statement, test: test, cases: cases, alternate: alternate)
    end

    def parse_when_expression
      expect(:when)
      tests = []

      loop do
        tests << parse_expression
        break if match %i(when else end)
        break unless expect(',', :LF, :then) === ','
      end

      block = node(:block_statement, body: parse_statements) unless match %i(when else end)
      node(:when_statement, tests: tests, consequent: block)
    end

    def parse_return_statement
      expect(:return)

      unless statement_modifier?
        argument = parse_expression unless match(:LF) || match(INLINE_TERM)
      end

      node(:return_statement, argument: argument)
    end

    def parse_delete_statement
      expect(:delete)
      position_token = lookahead
      argument = parse_member_expression(allow_calls: false)

      unless argument === :member_expression
        syntax_error("Expected member expression but got #{argument.type}", position_token)
      end

      node(:delete_statement, argument: argument)
    end

    # TODO: parse for statement modifier
    def parse_expression_statement
      expr = parse_expression
      stmt = node(:expression_statement, expression: expr)
      stmt = expect_statement_modifier(stmt) if statement_modifier?
      expect_terminator # NOTE: maybe it should be dropped?
      stmt
    end

    def parse_expression
      position_token = lookahead
      left = parse_conditional_expression

      if match(ASSIGNMENT_OPERATOR)
        syntax_error("Invalid left-hand side in assignment", position_token) unless valid_lhs?(left)
        node(:assignment_expression, operator: lex.value, left: left, right: parse_expression)
      else
        left
      end
    end

    def parse_conditional_expression
      left = parse_binary_expression

      if match('?')
        expect('?')
        consequent = parse_expression
        expect(':')
        alternate = parse_expression
        node(:conditional_expression, test: left, consequent: consequent, alternate: alternate)
      else
        left
      end
    end

    # The whole operator precedence logic is a copy-paste from esprima:
    # http://esprima.org/
    def parse_binary_expression
      left = parse_unary_expression
      return left unless match(BINARY_OPERATOR)

      token = lex
      right = parse_unary_expression

      token.precedence = binary_precedence(token)
      stack = [left, token, right]

      while (precedence = binary_precedence(lookahead)) > 0
        while (stack.size > 2) && (precedence <= stack[-2].precedence)
          right = stack.pop
          operator = stack.pop.value
          left = stack.pop
          stack << node(:binary_expression, operator: operator, left: left, right: right)
        end

        token = lex
        token.precedence = precedence

        stack << token
        stack << parse_unary_expression
      end

      i = stack.size - 1
      expr = stack[i]

      while i > 1
        expr = node(:binary_expression, operator: stack[i - 1].value, left: stack[i - 2], right: expr)
        i -= 2
      end

      expr
    end

    def parse_unary_expression
      if match(UNARY_OPERATOR)
        node(:unary_expression, operator: lex.value, argument: parse_member_expression)
      else
        parse_member_expression
      end
    end

    def parse_member_expression(allow_calls: true)
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
        elsif match('(') && allow_calls
          arguments = parse_list '(', ')', &method(:parse_call_argument)
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

    # TODO: parse shorter lambda expressions (crystal inspired): coll.forEach(&.prepare().save())
    def parse_primary_expression
      case lookahead.name
      when :BOOLEAN, :NIL, :NUMBER, :REGEXP
                       then node(:literal, value: lex.value)
      when :STRING     then node(:literal, value: "'%s'" % lex.value)
      when :identifier then node(:identifier, name: lex.value)
      when :new        then parse_new_expression
      when :'('        then parse_group_expression
      when :'['        then parse_array
      when :'{'        then parse_object
      when :'->'       then parse_lambda_expression
      else             unexpected_error(lex)
      end
    end

    def parse_new_expression
      expect(:new)
      position_token = lookahead
      expr = parse_member_expression

      case expr.type
      when :identifier, :member_expression
        node(:new_expression, callee: expr, arguments: [])
      when :call_expression
        node(:new_expression, callee: expr.callee, arguments: expr.arguments)
      else
        unexpected_error(position_token)
      end
    end

    def parse_lambda_expression
      expect('->')

      arguments = parse_lambda_arguments

      expect('{')
      block = node(:block_statement, body: parse_statements)
      expect('}')

      node(:lambda_expression, arguments: arguments, block: block)
    end

    # TODO: allow paren-less lambda arguments
    def parse_lambda_arguments
      position_token = lookahead

      if match '('
        arguments = parse_list '(', ')', &method(:parse_def_argument)
        expect(:LF) if match(:LF)
      else
        arguments = []
      end

      if duplicated_argument?(arguments)
        syntax_error("duplicated argument name", position_token)
      end

      arguments
    end

    def parse_group_expression
      expect('(')
      expression = parse_expression
      expect(')')
      node(:group_expression, expression: expression)
    end

    def parse_array
      elements = parse_list '[', ']', &method(:parse_expression)
      node(:array_expression, elements: elements)
    end

    def parse_object
      properties = parse_list '{', '}', &method(:parse_object_property)
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

    def parse_list(before, after, &block)
      list = []
      expect(before) if before

      if match(after)
        expect(after)
        return list
      end

      loop do
        list << (block.arity > 0 ? yield(list) : yield)
        expect(:LF) if match(:LF)
        token = expect(',', after)

        break if token === after
        lex and break if lookahead === after
      end

      list
    end

    private

    # TODO: attach position to nodes (eg: to generate source maps)
    def node(type_or_token, params = nil)
      if type_or_token.is_a?(RBS::Token)
        token = type_or_token

        if token === :identifier
          Node.new(token.name, name: token.value)
        else
          Node.new(token.name, value: token.value)
        end
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

    def statement_modifier?
      match %i(if unless while until)
    end

    def expect_statement_modifier(stmt)
      token = expect(:if, :unless, :while, :until)
      block = node(:block_statement, body: [stmt])
      node("#{token.name}_statement", test: parse_expression, consequent: block, alternate: nil)
    end

    def syntax_error(message, token)
      raise SyntaxError.new("#{message} at #{token.position}")
    end

    def unexpected_error(token, *expected)
      message = case expected.size
                when 0
                  "Unexpected token #{token.name} at #{token.position}"
                when 1
                  "Unexpected token #{token.name} at #{token.position}, expected #{expected.first}"
                else
                  "Unexpected token #{token.name} at #{token.position}, expected one of #{expected_tokens(expected)}"
                end
      raise ParseError.new(message, token: token)
    end

    def expected_tokens(expected)
      tokens = expected.map { |t| t.is_a?(String) ? "'#{t}'" : t }
      tokens.pop.tap { |t| tokens[tokens.size - 1] = "#{tokens.last} or #{t}" } if tokens.size > 1
      tokens.join(', ')
    end

    def match(type)
      lookahead === type
    end

    # TODO: push COMMENT tokens as nodes to the AST (?)
    def lex
      @index += 1
      while lexer.tokens[@index] === :COMMENT
        @index += 1
      end
      lexer.tokens[@index] or unexpected_error(:EOF)
    end

    def lookahead(peek = 1)
      while lexer.tokens[@index + peek] === :COMMENT
        peek += 1
      end
      lexer.tokens[@index + peek]
    end

    def valid_lhs?(left)
      left.type == :member_expression || (
        left.type == :identifier && left.name != 'this' && left.name != 'self'
      )
    end

    def duplicated_argument?(list)
      names = list.map do |a|
        case a.type
        when :identifier       then a.name
        when :splat_expression then a.expression.name
        end
      end
      list.size != names.uniq.size
    end

    def binary_precedence(token)
      BINARY_PRECEDENCE[token.name.to_s] || 0
    end
  end
end
