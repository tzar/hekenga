require 'hekenga/document_task'
module Hekenga
  class DSL
    class DocumentTask < Hekenga::DSL
      configures Hekenga::DocumentTask

      INVALID_BEHAVIOR_STRATEGIES = [:prompt, :cancel, :stop, :continue]
      VALID_WRITE_STRATEGIES = %i[delete_then_insert update]

      def batch_size(size)
        unless size.is_a?(Integer) && size > 0
          raise "Invalid batch size #{size.inspect}"
        end
        @object.batch_size = size
      end

      def when_invalid(val)
        unless INVALID_BEHAVIOR_STRATEGIES.include?(val)
          raise "Invalid value #{val}. Valid values for invalid_behavior are: #{INVALID_BEHAVIOR_STRATEGIES.join(", ")}."
        end
        @object.invalid_strategy = val
      end

      def write_strategy(strategy)
        unless VALID_WRITE_STRATEGIES.include?(strategy)
          raise "Invalid value #{strategy}. Valid values for write_strategy are: #{VALID_WRITE_STRATEGIES.join(", ")}."
        end
        @object.write_strategy = strategy
      end

      def scope(scope)
        @object.scope = scope
      end

      def always_write!
        @object.always_write = true
      end

      def use_transaction!
        @object.use_transaction = true
      end

      def parallel!
        @object.parallel = true
      end

      def timeless!
        @object.timeless = true
      end

      def skip_prepare!
        @object.skip_prepare = true
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
