require "hekenga/version"
require "hekenga/dsl"
require "hekenga/config"

module Hekenga
  class << self
    def configure
      yield(config)
    end
    def config
      @config ||= Hekenga::Config.new
    end
    def load!
      Dir.glob(File.join(config.abs_dir, "*.rb")).each do |path|
        require path
      end
    end
    def migration(&block)
      self.registry.push(
        Hekenga::DSL::Migration.new(&block)
      )
    end
    def registry
      @registry ||= []
    end
  end
end
