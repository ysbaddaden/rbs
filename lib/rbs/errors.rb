module RBS
  class Error < StandardError
  end

  class ParseError < Error
    attr_reader :token

    def initialize(message, options = nil)
      @token = options && options[:token]
      super message
    end
  end

  class SyntaxError < Error
  end
end
