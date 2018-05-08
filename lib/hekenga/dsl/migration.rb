require 'hekenga/migration'
require 'time'
module Hekenga
  class DSL
    class Migration < Hekenga::DSL
      configures Hekenga::Migration

      def batch_size(size)
        unless size.is_a?(Integer) && size > 0
          raise "Invalid batch size #{size.inspect}"
        end
        @object.batch_size = size
      end
      def created(stamp = nil)
        @object.stamp = Time.parse(stamp)
      end
      def task(description = nil, &block)
        @object.tasks.push Hekenga::DSL::SimpleTask.new(description, &block).object
      end
      def per_document(description = nil, &block)
        @object.tasks.push Hekenga::DSL::DocumentTask.new(description, &block).object
      end

      def inspect
        "<#{self.class} - #{@object.description} (#{@object.stamp.strftime("%Y-%m-%d %H:%M")})>"
      end
    end
  end
end

require 'hekenga/dsl/simple_task'
require 'hekenga/dsl/document_task'
