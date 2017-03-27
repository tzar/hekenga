module Hekenga
  class DSL
    attr_reader :object
    def initialize(description = nil, &block)
      @object = self.class.build_klass&.new
      description(description) if description
      instance_exec(&block)
    end
    def description(desc = nil)
      @object.description = desc if @object && desc
    end
    def inspect
      "<#{self.class} - #{self.description}>"
    end
    def self.configures(klass)
      @build_klass = klass
    end
    def self.build_klass
      @build_klass
    end
  end
end
require 'hekenga/dsl/migration'
