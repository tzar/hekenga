require 'hekenga/document_task'
module Hekenga
  class DSL
    class DocumentTask < Hekenga::DSL
      configures Hekenga::DocumentTask

      def scope(scope)
        @object.scope = scope
      end
      def parallel!
        @object.parallel = true
      end
      def timeless!
        @object.timeless = true
      end
      def disable_callback(callback, args = {})
        [args[:on]].flatten.compact.each do |model|
          @object.disable_rules.push({
            klass:    model,
            callback: callback
          })
        end
      end
      def setup(&block)
        @object.setups.push block
      end

      def filter(&block)
        @object.filters.push block
      end

      def up(&block)
        @object.ups.push block
      end

      def down(&block)
        @object.downs.push block
      end
    end
  end
end
