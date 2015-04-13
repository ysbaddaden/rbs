module RBS
  class Indenter
    attr_reader :formatter

    def initialize(formatter)
      @formatter = formatter
    end

    def compile(type: "iife", spaces: 2)
      formatted = @formatter.compile(type: type)
      indent(formatted, spaces: spaces)
    end

    private

    def indent(output, spaces:)
      deep = 0
      indent = " " * spaces

      output.each_line.map do |line|
        if line =~ /\A\s*\}/
          deep -= 1
        elsif line =~ /\{\s*\Z/
          rs = indent * deep
          deep += 1
        end

        if line =~ /\A\s*\Z/
          rs = "\n"
        else
          rs ||= indent * deep
          rs += line.strip + "\n"
        end

        if line =~ /\A\s*\}.+\{\s*\Z/
          deep += 1
        end

        rs
      end.join
    end
  end
end
