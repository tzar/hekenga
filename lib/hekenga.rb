require "hekenga/version"
require "hekenga/migration"
require "hekenga/dsl"
require "hekenga/config"
require "hekenga/irreversible"
require "hekenga/virtual_method"

module Hekenga
  class << self
    def configure
      yield(config)
    end
    def config
      @config ||= Hekenga::Config.new
    end
    def load_all!
      return if @loaded
      Dir.glob(File.join(config.abs_dir, "*.rb")).each do |path|
        require path
      end.tap { @loaded = true }
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
