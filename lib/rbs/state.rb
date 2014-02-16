module RBS
  class State < Array
    def is(name)
      last == name
    end

    alias_method :===, :is
  end
end
