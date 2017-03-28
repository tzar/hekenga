require 'hekenga/irreversible'
module Hekenga
  class SimpleTask
    attr_reader :ups, :downs
    attr_accessor :description
    def initialize
      @ups   = []
      @downs = []
    end

    def validate!
      raise Hekenga::Invalid.new(self, :ups, "missing") unless ups.any?
    end

    def up!
      @ups.each do |block|
        block.call
      end
    end

    def down!
      raise Hekenga::Irreversible.new(self) unless reversible?
      @downs.each do |block|
        block.call
      end
    end

    def reversible?
      downs.any?
    end
  end
end
