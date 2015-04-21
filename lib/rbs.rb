require "rbs/version"
require "rbs/lexer"
require "rbs/lexer/rewriter"
require "rbs/parser"
require "rbs/parser/rewriter"
require "rbs/formatter"
require "rbs/indenter"

module RBS
  def self.compile_file(path, options = {})
    compile(File.read(path), options)
  end

  def self.compile(source, indent: true, **options)
    lexer = RBS::Lexer::Rewriter.new(RBS::Lexer.new(source))
    parser = RBS::Parser::Rewriter.new(RBS::Parser.new(lexer))

    formatter = if indent
                  RBS::Indenter.new(RBS::Formatter.new(parser))
                else
                  RBS::Formatter.new(parser)
                end
    formatter.compile(options)
  end
end
