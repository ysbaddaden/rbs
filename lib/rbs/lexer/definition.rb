module RBS
  KEYWORDS = %i(
    def delete return then do end prototype object
    if unless else elsif case when while until loop for in own of
    break next new begin rescue ensure
    and or not typeof instanceof
  )

  OPERATORS = %i(
    -> += -= *= /= %= &= |= ^= ||= >>= <<=
    + - ~ * / % && || & | ^ << >> == != <= >= => < >
    ... .. . , = : ? !
  )
  ASSIGNMENT_OPERATOR = %i(= += -= *= /= %= &= |= ^= ||= >>= <<=)
  BINARY_OPERATOR = %i(+ - ~ * / % && || & | ^ << >> == != <= >= => < > ... ..)
  UNARY_OPERATOR = %i(+ - ~ ! typeof)

  PARENS = %i(\( \) { } [ ])

  DETECT_REGEXP = %i(
    \( , = : [ ! & | ? { } ; ~ + - * % ^ < >
    return when if else elsif unless
  )

  ARGUMENT = %i(
    BOOLEAN NIL NUMBER STRING REGEXP identifier
    \( [ { -> not typeof new
  ) # - + * ~

  class Lexer
    module RE
      def self.to_regexp(words, bound: false) # :nodoc:
        map = words.map { |name| Regexp.escape(name.to_s) }
        Regexp.new('\A(' + map.join('|') + ')' + (bound ? '\\b' : ''))
      end

      COMMENT =    /\A((?:#.*\n\s*)*#[^\n]*)/
      LINEFEED =   /\A\n/
      SEMICOLON =  /\A(;)/
      BOOLEAN =    /\A(true|false)\b/
      NIL =        /\A(null|nil|undefined)\b/
      FLOAT =      /\A((\d+)?\.\d+)([eE][-+]?\d+)?\b/
      INTEGER =    /\A(\d+)([eE][-+]?\d+)?\b/
      REGEXP =     /\A\/[^=]/
      REGEXP2 =    /\A%r([^\w])/
      KEYWORDS =   to_regexp(KEYWORDS, bound: true)
      OPERATORS =  to_regexp(OPERATORS)
      PARENS =     to_regexp(PARENS)
      WHITESPACE = /\A([ \t\r]+)/
      #STRING =    /\A('(\.|[^\'])*')/
      STRING =     /\A(')/
      STRING2 =    /\A(")/
      STRING3 =    /\A%([^\w\s=])/
      WORDS =      /\A%w([^\w])/
      IDENTIFIER = /\A([$A-Z\_a-z][$A-Z\_a-z0-9]*)/
    end
  end
end
