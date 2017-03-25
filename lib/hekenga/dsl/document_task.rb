module Hekenga
  class DSL
    class DocumentTask < Hekenga::DSL
      attr_reader :parallel, :disable_rules, :setups, :filters
      def scope(scope)
        @scope = scope if scope
        @scope
      end
      def parallel!
        @parallel = true
      end
      def disable_callbacks(args = {})
        [args[:on]].flatten.compact.each do |model|
          (@disable_rules ||= []).push({
            klass: model,
            all:   true
          })
        end
      end
      def disable_callback(callback, args = {})
        [args[:on]].flatten.compact.each do |model|
          (@disable_rules ||= []).push({
            klass:    model,
            callback: callback
          })
        end
      end
      def setup(&block)
        (@setups ||= []).push(&block)
      end

      def filter(&block)
        (@filters ||= []).push(&block)
      end

      def up(&block)
        (@ups ||= []).push(&block)
      end

      def down(&block)
        (@downs ||= []).push(&block)
      end
    end
  end
end
