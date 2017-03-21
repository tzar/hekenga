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

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_runtime_dependency "mongoid", "~> 5.0"
end
