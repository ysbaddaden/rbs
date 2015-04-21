require 'rake'
require 'rake/testtask'

$:.unshift File.expand_path("../lib", File.realpath(__FILE__))
require 'rbs'

task :default => :test

desc 'Run all the test suites'
task :test => %i(test:unit test:integration)

desc 'Run the unit test suite'
Rake::TestTask.new(:'test:unit') do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Run the integration test suite'
task :'test:integration' do |t|
  Dir.mkdir('tmp') unless Dir.exists?('tmp')
  Dir.mkdir('tmp/integration') unless Dir.exists?('tmp/integration')

  Dir['test/integration/*_test.rbs'].each do |input|
    output = input.sub(/^test/, "tmp").sub(/\.rbs$/, ".js")
    source = RBS.compile_file(input)
    File.write(output, source)
  end

  pid = spawn(
    'node_modules/.bin/mocha',
    '--ui', 'tdd',
    '--reporter', 'dot',
    'test/integration/test_helper.js',
    'tmp/integration/*_test.js'
  )
  _, status = Process.wait2(pid)
  exit status.exitstatus
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
