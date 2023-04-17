# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hekenga/version'

Gem::Specification.new do |spec|
  spec.name          = "hekenga"
  spec.version       = Hekenga::VERSION
  spec.authors       = ["Tapio Saarinen"]
  spec.email         = ["admin@bitlong.org"]

  spec.summary       = %q{Sophisticated migration framework for mongoid, with the ability to parallelise via ActiveJob.}
  spec.homepage      = "https://github.com/tzar/hekenga"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.4.6"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "database_cleaner-mongoid"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"

  spec.add_runtime_dependency "mongoid", ">= 6"
  spec.add_runtime_dependency "activejob", ">= 5"
  spec.add_runtime_dependency "thor"
end
