require 'rbs/state'
require 'rbs/lexer/definition'
require 'rbs/lexer/token'

module RBS
  class ParseError < StandardError
  end

  class Lexer
    attr_reader :input, :index, :line, :column, :state

    def initialize(input)
      @input = input
      @index, @line, @column = 0, 1, 1
      @state = State.new
      @embed = []
    end

    def lex
      tokens.shift
    end

    def tokens
      tokenize if @tokens.nil?
      @tokens
    end

    private

      def tokenize
        @tokens = []

        loop do
          str = input[index..-1]

          if str.empty?
            token(:EOF)
            break
          end

          unless state === :embed && match_embed(str)
            match(str)
          end
        end
      end

      def match(str)
        if    m = str.match(RE::COMMENT)    then name = :COMMENT
        elsif     str.match(RE::LINEFEED)   then linefeed
        elsif m = str.match(RE::SEMICOLON)  then name = m[0]
        elsif m = str.match(RE::BOOLEAN)    then name = :BOOLEAN
        elsif m = str.match(RE::NIL)        then name = :NIL
        elsif m = str.match(RE::FLOAT)      then name = :NUMBER
        elsif m = str.match(RE::INTEGER)    then name = :NUMBER
        elsif     str.match(RE::REGEXP)     then regexp(str)
        elsif     str.match(RE::REGEXP2)    then regexp2($1, closing_quote($1))
        elsif     str.match(RE::WORDS)      then words($1, closing_quote($1))
        elsif     str.match(RE::STRING)     then string(str, "'", "'")
        elsif     str.match(RE::STRING2)    then embedable_string('"', '"')
        elsif     str.match(RE::STRING3)    then embedable_string($1, closing_quote($1))
        elsif m = str.match(RE::KEYWORDS)   then name = m[0]
        elsif m = str.match(RE::OPERATORS)  then name = m[0]
        elsif m = str.match(RE::PARENS)     then name = m[0]
        elsif m = str.match(RE::IDENTIFIER) then name = :identifier
        elsif m = str.match(RE::WHITESPACE) then name = :whitespace
        else
          str =~ /\A([^\s]+)/
          raise ParseError, "Unknown token #{$1} at #{line},#{column}"
        end

        token(name, m[0]) if name
      end

      def linefeed
        token(:LF)
        @line += 1
        @column = 0
        consume(1)
      end

      def match_embed(str)
        if str =~ /\A#\{/
          token('+', '+')
          token('(', '(')
          return true
        end

        if str =~ /\A\}/
          quotes = @embed.pop

          if str[1] == quotes.last
            token(')', ')')
            token(')', ')')
            state.pop # embed
            state.pop # string
          else
            token(')', ')')
            token('+', '+')
            consume(-1)
            unput(quote(*quotes))
            state.pop # embed
          end
          return true
        end

        false
      end

      def words(*quotes)
        consume(2)
        str = input[index..-1]
        words = match_literal(str, quotes, embeddable: false)
        consume(words.size)

        token('[', '[', consume: false)
        words.strip.split(/\s+/).each do |word|
          token(:STRING, word, consume: false)
        end
        token(']', ']', consume: false)
      end

      def embedable_string(*quotes)
        @embed << quotes

        consume(1) unless quotes.first == '"'
        string(input[index..-1], *quotes)

        if state === :string
          token(')', ')')
          state.pop
        end
      end

      def string(str, *quotes)
        value = match_literal(str, quotes, embeddable: quotes.first != "'")
        token(:STRING, value)

        if state === :string
          token(')', ')')
          consume(-1)
          state.pop
        end
      end

      def embed
        if state === :string
          consume(-1)
        else
          token('(', '(')
          state << :string
          consume(-2)
        end
        state << :embed
      end

      def regexp(str)
        return token('/', '/') unless potential_regexp?

        idx = 1
        loop do
          m = str[idx..-1].index('/')
          raise ParseError, 'Unterminated regular expression' if m.nil?

          idx += m + 1;
          if str[(idx - 2)...idx] != '\/'
            if mm = str[idx..-1].match(/\A[gimy]*/)
              idx += mm[0].size
            end
            return token(:REGEXP, str[0...idx])
          end
        end
      end

      def potential_regexp?
        i = tokens.size - 1
        i -= 1 if tokens[i] === :whitespace
        !tokens[i] || tokens[i] === DETECT_REGEXP
      end

      def regexp2(*quotes)
        consume(2)
        str = input[index..-1]
        regexp = match_literal(str, quotes, embeddable: false)
        consume(regexp.size)

        if opts = input[index..-1].match(/\A[gimy]*/)
          consume(opts[0].size)
        end
        token(:REGEXP, '/' + regexp.gsub(%r(([^\\]|^)/), '\1\\/') + '/' + opts[0], consume: false)
      end

      def closing_quote(quote)
        case quote
        when '(' then ')'
        when '[' then ']'
        when '{' then '}'
        else quote
        end
      end

      def quote(opening, closing = nil)
        opening == '"' || opening == "'" ? opening : '"'
      end

      def match_literal(str, quotes, embeddable: true)
        idx = 1
        value = ''
        equote = Regexp.escape(quotes.last)
        re = /\A([^#{equote}]*#{equote})/

        loop do
          if m = str[idx..-1].match(re)
            text = m[0]

            if embeddable && (j = text.index(/#\{/))
              value += text[0...j] + quotes.last
              embed
              break
            else
              value += text
              break unless text[-2..-1] == "\\#{quotes.last}"
              idx += text.size
            end
          else
            raise ParseError, "Unterminated string"
          end
        end

        @line += value.count("\n")
        consume(2) # the opening + closing quotes
        return value[0..-2]
      end

      def token(name, value = nil, consume: true)
        #puts ['TOKEN:', name, value, line, column].join(' ')
        @tokens << Token.new(name.to_sym, value, line, column)
        consume(value.size) if consume && value
      end

      def consume(size)
        @index += size
        @column += size
      end

      def unput(str)
        if index > 0
          @input = input[0...index] + str + input[index..-1]
        else
          @input = str + input[index..-1]
        end
      end
  end
end

#def debug(code)
#  lexer = Lexer.new(code)
#
#  #while name = lexer.lex()
#  #  console.log("#{name} '#{lexer.yytext}' #{lexer.yyleng} #{lexer.yyline},#{lexer.yycolumn}")
#  #end
#
#  console.log(lexer.tokens.map(->(t) { return t.inspect() }).join(' '))
#  console.log("")
#end

#debug("def A(a)\nreturn a + 1\n\n\n end")
#debug("def A default = nil\nreturn a + 1\n end")
#debug("describe 'DSL', -> {\n  it 'must be ok', -> {\n    assert.ok true\n }\n}")
#debug("lmbd = ->(rs) { doSomething() }")
#debug("'I can\\'t be damned.'")
#debug("'This is a string\nspanning on\nmultiple lines'")
#debug('"total: #{amount} €"')
#debug('"debug: #{hello} #{world}".test(something)')
#debug('/azerty/i')
#debug('# this is a comment')
#debug("# this is a comment\n# spanning on\n# multiple lines")
#debug("select = readkey() - 1 #comment")
#debug("{ a: -> {},\n #comment\nb: -> {} }")
#debug('"unknown token #{self.line},#{self.column}"')

