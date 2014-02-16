require 'rbs/lexer/token'
require 'rbs/lexer/definition'

module RBS
  class Rewriter
    SKIP_LF_AFTER = OPERATORS + %i(and or not LF COMMENT \( { [ ,)
    SKIP_LF_BEFORE = %i(, : \) } ]) # = .
    MODIFIER_KEYWORDS = %i(if unless while until for)
    UNARY = %i(- + ~ *) # we consider splat operator as unary-like

    attr_reader :tokens, :rs, :index

    def initialize(tokens)
      @tokens = tokens
      @index = 0
      @state = State.new
      @rs = []
    end

    def rewrite
      while token = tokens[index]
        @index += 1

        case token
        when :whitespace
          detect_call_without_parens(token)
          next
        when :LF, *MODIFIER_KEYWORDS
          close_opened_calls(token)
          next if token.is(:LF) && skip_linefeed?
        when '{'
          if state.is(:lambda_def)
            state.pop # :lambda_def
            state.push :lambda
          else
            state.push :object
          end
        when '}'
          close_opened_calls(token)
          state.pop # :lambda or :object
        when '('
          state.push(:paren)
        when ')'
          close_opened_calls(token)
          state.pop # :paren
        when '->'
          state.push :lambda_def
        when ';'
          push(:LF, nil, token)
          next
        when :keyword
          next if dottable_keyword(token)
        #when :COMMENT
        #  next
        when :EOF
          close_opened_calls(token)
          return rs
        end

        rs << token
      end

      rs
    end

    private

      def detect_call_without_parens(token)
        if parens_less_call?
          state.push :call
          push('(', '(', token)
        end
      end

      def call_without_parens?
        rs.last === :identifier && (
          tokens[index] === :argument ||
          (tokens[index] === UNARY && !(tokens[index + 1] === %i(whitespace LF)))
        )
      end

      def close_opened_calls(token)
        while state.is(:call)
          token(')', ')', token)
          state.pop # :call
        end
      end

      def dottable_keyword(token)
        if rs.last === %i(def .) || lookahead === ':' || rs[-2..-1].map(&:name) == %i(def +)
          push(:identifier, token.name, token)
        end
      end

      def skip_linefeed?
        rs.last === SKIP_LF_AFTER || lookahead === SKIP_LF_BEFORE
      end

      def lookahead
        tokens[index] === :whitespace ? tokens[index] : tokens[index + 1]
      end

      def push(name, value, token)
        rs << Token.new(name, value, token.line, token.column)
      end
  end
end
