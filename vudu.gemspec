# -*- encoding: utf-8 -*-

$:.push File.expand_path('../lib', __FILE__)
require 'vudu/version'

Gem::Specification.new do |s|
  s.name = "vudu"
  s.summary = "A Ruby interface to the Vudu (vudu.com) Disc2Digital API."
  s.description = "A Ruby interface to the Vudu (vudu.com) Disc2Digital API enabling an automated way to verify if your movie title qualifies for the Ultraviolet Disc2Digital upgrade."
  s.version = Vudu::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Nate"]
  s.email = ["jfa@packetdamage.com"]
  s.homepage = "http://github.com/jfx41/vudu"

  # Runtime dependencies
  s.add_dependency "bigdecimal", ">= 1.1.0"
  s.add_dependency "diff-lcs", ">= 1.2.1"
  s.add_dependency "open-uri"
  s.add_dependency "json"

  # Development dependencies
  #s.add_development_dependency "rake"
  #s.add_development_dependency "rspec", "~> 2.0"
  #s.add_development_dependency "mocha", ">= 0.9"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
