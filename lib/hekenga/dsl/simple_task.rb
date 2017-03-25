module Hekenga
  class DSL
    class SimpleTask < Hekenga::DSL
      attr_reader :ups, :downs
      def up(&block)
        (@ups ||= []).push(block)
      end
      def down(&block)
        (@downs ||= []).push(block)
      end
    end
  end
end
