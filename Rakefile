require 'rake'
require 'rake/testtask'
require 'rdoc/task'

task :default => :test

desc 'Run the test suite'
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

Rake::RDocTask.new do |rdoc|
  rdoc.title = "RBS"
  rdoc.main = "README.rdoc"
  rdoc.rdoc_dir = "doc"
  rdoc.rdoc_files.include("README.rdoc", "lib/**/*.rb")
  rdoc.options << "--charset=utf-8"
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
