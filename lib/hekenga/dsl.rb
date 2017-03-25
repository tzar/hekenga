module Hekenga
  class DSL
    def initialize(description = nil, &block)
      description(description) if description
      instance_exec(&block)
    end
    def description(desc = nil)
      @description = desc if desc
      @description
    end
    def inspect
      "<#{self.class} - #{self.description}>"
    end
  end
end
require 'hekenga/dsl/migration'
