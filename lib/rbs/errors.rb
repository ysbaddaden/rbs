module RBS
  class ParseError < StandardError
    attr_reader :token

    def initialize(message, options = nil)
      @token = options && options[:token]
      super message
    end
  end
end
