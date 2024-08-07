require 'hekenga/irreversible'
require 'hekenga/base_iterator'
module Hekenga
  class DocumentTask
    attr_reader :ups, :downs, :setups, :filters, :after_callbacks
    attr_accessor :parallel, :scope, :timeless, :batch_size, :cursor_timeout
    attr_accessor :description, :invalid_strategy, :skip_prepare, :write_strategy
    attr_accessor :always_write, :use_transaction

    def initialize
      @ups              = []
      @downs            = []
      @setups           = []
      @filters          = []
      @after_callbacks  = []
      @invalid_strategy = :continue
      @write_strategy   = :update
      @skip_prepare     = false
      @batch_size       = nil
      @always_write     = false
      @use_transaction  = false
      @cursor_timeout   = Hekenga::BaseIterator::DEFAULT_TIMEOUT
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
