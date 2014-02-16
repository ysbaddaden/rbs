require File.expand_path('../lib/rbs/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Julien Portalier"]
  gem.email         = ["julien@portalier.com"]
  gem.description   = ""
  gem.summary       = ""
  gem.homepage      = "http://github.com/ysbaddaden/rbs"
  gem.license       = "MIT"

  gem.files         = `git ls-files | grep -Ev '^(Gemfile|test)'`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "rbs"
  gem.require_paths = ["lib"]
  gem.version       = RBS::VERSION::STRING

  gem.cert_chain    = ['certs/ysbaddaden.pem']
  gem.signing_key   = File.expand_path('~/.ssh/gem-private_key.pem') if $0 =~ /gem\z/

  gem.add_development_dependency 'minitest'
end
