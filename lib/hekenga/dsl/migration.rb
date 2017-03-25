require 'time'
module Hekenga
  class DSL
    class Migration < Hekenga::DSL
      attr_reader :tasks

      def created(stamp = nil)
        puts stamp
        @created = Time.parse(stamp) if stamp
        @created
      end
      def task(description = nil, &block)
        (@tasks ||= []).push Hekenga::DSL::SimpleTask.new(description, &block)
      end
      def per_document(description = nil, &block)
        (@tasks ||= []).push Hekenga::DSL::DocumentTask.new(description, &block)
      end

      def inspect
        "<#{self.class} - #{self.description} (#{self.created.strftime("%Y-%m-%d %H:%M")})>"
      end
    end
  end
end

require 'hekenga/dsl/simple_task'
require 'hekenga/dsl/document_task'
