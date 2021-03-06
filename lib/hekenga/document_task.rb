require 'hekenga/irreversible'
module Hekenga
  class DocumentTask
    attr_reader :ups, :downs, :setups, :filters
    attr_accessor :parallel, :scope, :timeless
    attr_accessor :description, :invalid_strategy, :skip_prepare
    def initialize
      @ups              = []
      @downs            = []
      @setups           = []
      @filters          = []
      @invalid_strategy = :prompt
      @skip_prepare     = false
    end

    def validate!
      raise Hekenga::Invalid.new(self, :ups, "missing") unless ups.any?
    end

    def up!(context, document)
      @ups.each do |block|
        context.instance_exec(document, &block)
      end
    end

    def down!(context, document)
      raise Hekenga::Irreversible.new(self) unless reversible?
      @downs.each do |block|
        context.instance_eval(document, &block)
      end
    end

    def reversible?
      downs.any?
    end
  end
end
