require "pp"
require "thor"
require "rbs"

module RBS
  class CLI < Thor
    package_name "rbs"
    map "-v" => "version", "--version" => "version"

    desc "compile [INPUT]", "Compiles to JavaScript"
    option :output,                                  aliases: %w(-o), desc: "Specify output file"
    option :module,                 default: "iife", aliases: %w(-m), desc: "Either amd, iife or raw"
    option :indent, type: :boolean, default: true
    option :spaces, type: :numeric, default: 2

    def compile(input = nil)
      source = read(input)
      parser = RBS::Parser.new(RBS::Rewriter.new(RBS::Lexer.new(source)))
      formatter = RBS::Formatter.new(parser)

      code = if options[:indent]
               indenter = RBS::Indenter.new(formatter)
               indenter.compile(type: options[:module], spaces: options[:spaces])
             else
               formatter.compile(type: options[:module])
             end

      if options[:output].nil? || options[:output] == "-"
        STDOUT.puts(code)
      else
        File.open(options[:output], "w") { |f| f.puts(code) }
      end
    end


    desc "ast [INPUT]", "Prints the Abstract Syntax Tree"

    def ast(input = nil)
      source = read(input)
      lexer = RBS::Rewriter.new(RBS::Lexer.new(source))
      parser = RBS::Parser.new(lexer)
      pp parser.parse.to_h
    end


    desc "tokens [INPUT]", "Prints the lexed tokens"

    def tokens(input = nil)
      source = read(input)
      lexer = RBS::Rewriter.new(RBS::Lexer.new(source))
      p lexer.tokens
    end


    desc "version", ""
    def version
      puts RBS.version_string
    end


    private

    def read(input)
      input && File.read(input) || STDIN.read
    end
  end
end
