require "pp"
require "thor"
require "rbs"

module RBS
  class CLI < Thor
    package_name "rbs"
    map "-v" => "version", "--version" => "version"

    desc "compile [INPUT]", "Compiles to JavaScript"
    option :output,                                        aliases: %w(-o), desc: "Specify output file"
    option :module,                       default: "iife", aliases: %w(-m), desc: "Either amd, iife or raw"
    option :experimental, type: :boolean, default: false,  aliases: %w(-e), desc: "Enable experimental features"
    option :indent,       type: :boolean, default: true
    option :spaces,       type: :numeric, default: 2

    def compile(input = nil)
      source = read(input)
      lexer = RBS::Rewriter.new(RBS::Lexer.new(source))
      parser = RBS::Parser::Rewriter.new(RBS::Parser.new(lexer))
      formatter = RBS::Formatter.new(parser)

      formatter_options = {
        type: options[:module],
        experimental: options[:experimental]
      }

      code = if options[:indent]
               indenter = RBS::Indenter.new(formatter)
               indenter.compile(spaces: options[:spaces], **formatter_options)
             else
               formatter.compile(formatter_options)
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
      parser = RBS::Parser::Rewriter.new(RBS::Parser.new(lexer))
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
