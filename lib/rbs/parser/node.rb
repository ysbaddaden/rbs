module RBS
  class Node
    attr_accessor :type
    attr_reader :params
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
      if params.has_key?(name)
        return params[name]
      end

      if name =~ /\A(.+)=\Z/
        key = $1.to_sym
        return params[key] = args[0] if params.has_key?(key)
      end

      super
    end

    def respond_to?(name)
      super || params.has_key?(name)
    end

    def inspect
      to_h.to_s
    end

    def to_h
      { type: type }.merge(Hash[params_as(:to_h)])
    end

    def as_json
      { type: camelize(type) }.merge(Hash[params_as(:as_json)])
    end

    private

    def params_as(method)
      params.map do |key, value|
        value = case value
                when Array     then value.map(&method)
                when RBS::Node then value.__send__(method)
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
