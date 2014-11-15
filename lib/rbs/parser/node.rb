module RBS
  class Node
    attr_reader :type, :params
    undef_method :test

    def initialize(type, params = nil)
      @type = type.to_sym
      @params = params || {}
    end

    def is(type)
      self.type == type.to_sym
    end

    def ===(type)
      if type.is_a?(Array)
        type.any? { |t| is(t) }
      else
        is(type)
      end
    end

    def method_missing(name, *args)
      return params[name] if params.has_key?(name)
      super
    end

    def respond_to?(name)
      super || params.has_key?(name)
    end

    def inspect
      { type: type }.merge(params).to_s
    end

    def as_json
      { type: camelize(type) }.merge(Hash[params_as_json])
    end

    private

    def params_as_json
      params.map do |key, value|
        value = case value
                when Array     then value.map(&:as_json)
                when RBS::Node then value.as_json
                else                value
                end
        [key, value]
      end
    end

    def camelize(str)
      str.to_s.gsub(/(^\w|_\w)/) { |s| s.sub('_', '').upcase }
    end
  end
end
