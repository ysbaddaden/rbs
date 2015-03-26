module RBS
  class Indenter
    attr_reader :formatter

    def initialize(formatter)
      @formatter = formatter
    end

    def compile(raw: false, spaces: 2)
      output = @formatter.compile(raw: raw)
      deep = 0
      indent = " " * spaces

      output.each_line.map do |line|
        if line =~ /\{\s*\Z/
          rs = indent * deep
          deep += 1
        elsif line =~ /\A\s*\}/
          deep -= 1
        end

        if line =~ /\A\s*\Z/
          "\n"
        else
          rs ||= indent * deep
          rs + line
        end
      end.join
    end
  end
end
