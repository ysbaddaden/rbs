require File.expand_path("../lib/rbs/version", __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Julien Portalier"]
  gem.email         = ["julien@portalier.com"]
  gem.summary       = "Ruby inspired language that transcompiles to simple JavaScript"
  gem.description   = <<-EOF
    A Ruby inspired language that transcompiles to simple JavaScript. The main
    goal is to bring some sanity to Browser programming with a simple,
    beautiful and zen language.

    While Opal aims to implement Ruby over the JavaScript language, RBS aims to
    bring only a subset of the Ruby language so it's possible to develop for
    any existing framework (eg: backbone, angular, ember), or even drop RBS in
    favor to the compiled JavaScript (why not?)
  EOF
  gem.homepage      = "http://github.com/ysbaddaden/rbs"
  gem.license       = "MIT"

  gem.files         = `git ls-files | grep -Ev '^(Gemfile|test)'`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "rbs"
  gem.require_paths = ["lib"]
  gem.version       = RBS::VERSION::STRING

  gem.bindir        = "bin"
  gem.executables   = ["rbs"]

  gem.cert_chain    = ["certs/ysbaddaden.pem"]
  gem.signing_key   = File.expand_path("~/.ssh/gem-private_key.pem") if $0 =~ /gem\z/

  gem.add_runtime_dependency     "thor"
  gem.add_development_dependency "minitest"
end
