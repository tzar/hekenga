require "hekenga/version"
require "hekenga/dsl"

module Hekenga
  class << self
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
