# Stub
class MyModel
  def self.where(*args)
    self
  end
end
# You can stack multiple tasks within one overall logical migration
Hekenga.migration do
  description "Example usage"
  created "2016-04-03 14:00"

  # Simple tasks have an up and a down and run in one go
  task "Set foo->bar by default on MyModel" do
    up do
      MyModel.all.set(foo: 'bar')
    end
    down do
      MyModel.all.unset(:foo)
    end
  end

  # Per document tasks run a block of code per document, with the ability to
  # filter which documents are loaded by:
  # - scope
  # - arbitrary block
  # Jobs can be run in parallel via ActiveJob.
  # Callbacks can be disabled for the context of the job either globally via
  # disable_callbacks or specifically via disable_callback, with multiple models
  # optionally targetted via the `on` param.
  # A setup block is also provided (this must be able to be run multiple times!)
  # per_document migrations should be resumable/retryable..
  # errors should never result in data loss, and should be logged to a migration
  # output model
  per_document "Set MyModel.zap to a random number if unset" do
    scope MyModel.where(zap: nil)
    parallel!
    timeless!
    disable_callback :reindex, on: MyModel

    setup do
      @max_rand = 100
    end

    filter do |document|
      document.zap.nil?
    end

    up do |document|
      document.zap = rand(@max_rand)
    end
  end
end
