require 'rbs/lexer/token'
require 'rbs/lexer/definition'

module RBS
  class Rewriter
    SKIP_LF_AFTER = OPERATORS + %i(and or not LF COMMENT \( { [ ,)
    SKIP_LF_BEFORE = %i(, : \) } ]) # = .
    MODIFIER_KEYWORDS = %i(if unless while until for)
    UNARY = %i(- + ~ *) # we consider splat operator as unary-like

    attr_reader :lexer, :index, :state

    def initialize(lexer)
      @lexer = lexer
    end

    def lex
      tokens.shift
    end

    def tokens
      rewrite if @tokens.nil?
      @tokens
    end

    def rewrite
      @index = 0
      @tokens = []
      @state = State.new

      while token = lexer.tokens[index]
        @index += 1

        case token.name
        when :whitespace
          detect_call_without_parens(token)
          next
        when :LF, *MODIFIER_KEYWORDS
          close_opened_calls(token)
          next if token.is(:LF) && skip_linefeed?
        when :'{'
          if state.is(:lambda_def)
            state.pop # :lambda_def
            state.push :lambda
          else
            state.push :object
          end
        when :'}'
          close_opened_calls(token)
          state.pop # :lambda or :object
        when :'('
          state.push(:paren)
        when :')'
          close_opened_calls(token)
          state.pop # :paren
        when :'->'
          state.push :lambda_def
        when :';'
          close_opened_calls(token)
          push(:LF, nil, token)
          next
        when *KEYWORDS
          next if dottable_keyword(token)
        #when :COMMENT
        #  next
        when :EOF
          close_opened_calls(token)
          return tokens << token
        end

        tokens << token
      end

      tokens
    end

    private

      def detect_call_without_parens(token)
        if call_without_parens?
          state.push :call
          push('(', '(', token)
        end
      end

      def call_without_parens?
        tokens.last === :identifier && (
          lexer.tokens[index] === :argument ||
          (lexer.tokens[index] === UNARY && !(lexer.tokens[index + 1] === %i(whitespace LF)))
        )
      end

      def close_opened_calls(token)
        while state.is(:call)
          push(')', ')', token)
          state.pop # :call
        end
      end

      def dottable_keyword(token)
        if tokens.last === %i(def .) || lookahead === ':' ||
            (tokens.size > 1 && tokens[-2..-1].map(&:name) == %i(def +))
          push(:identifier, token.name, token)
        end
      end

      def skip_linefeed?
        tokens.last === SKIP_LF_AFTER || lookahead === SKIP_LF_BEFORE
      end

      def lookahead
        lexer.tokens[index] === :whitespace ? lexer.tokens[index] : lexer.tokens[index + 1]
      end

      def push(name, value, token)
        tokens << Token.new(name, value, token.line, token.column)
      end
  end
end
