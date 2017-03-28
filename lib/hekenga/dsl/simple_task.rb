require 'hekenga/simple_task'
module Hekenga
  class DSL
    class SimpleTask < Hekenga::DSL
      configures Hekenga::SimpleTask
      def up(&block)
        @object.ups.push(block)
      end
      def down(&block)
        @object.downs.push(block)
      end
    end
  end
end
