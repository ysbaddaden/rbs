require 'rake'
require 'rake/testtask'

task :default => :test

desc 'Run the test suite'
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Enumerate all annotations'
task :notes do
  Dir['{lib,test}/**/*.rb'].each do |filename|
    notes = File.readlines(filename).grep(/(note|todo|optimize|fixme):/i)
    next if notes.empty?

    puts filename
    puts notes.map { |note| note.gsub(/^\s*#\s*/, "").chomp }.join("\n")
    puts
  end
end

def count_lines(*paths)
  paths.reduce(0) do |count, path|
    Dir[path].reduce(count) do |c, filename|
      lines = File.readlines(filename)
      c + lines.size - lines.grep(/^\s*$/).size
    end
  end
end

desc 'Code statistics'
task :stats do
  lexer = count_lines('lib/rbs/lexer.rb', 'lib/rbs/lexer/*.rb')
  parser = count_lines('lib/rbs/parser.rb', 'lib/rbs/parser/*.rb')
  formatter = count_lines('lib/rbs/formatter.rb', 'lib/rbs/formatter/*.rb')
  code = count_lines('lib/**/*.rb')
  test = count_lines('test/**/*.{rb,js}')
  ratio = 1.0 / code * test

  puts "     Lexer LOC: #{lexer}"
  puts "    Parser LOC: #{parser}"
  puts " Formatter LOC: #{formatter}"
  puts
  puts "      Code LOC: #{code}"
  puts "      Test LOC: #{test}"
  puts " Code to Test Ratio: 1:#{ratio.round(1)}"
end
