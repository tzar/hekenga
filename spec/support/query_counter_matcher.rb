RSpec::Matchers.define :query_model do |model|
  chain :times do |count|
    @expected_count = count
  end

  supports_block_expectations

  match do |block|
    @expected_count ||= 1
    @collection_name = model.collection_name.to_s

    subscriber = QueryCountSubscriber.new(@collection_name)
    client = model.collection.client
    client.subscribe(Mongo::Monitoring::COMMAND, subscriber)

    begin
      block.call
    ensure
      client.unsubscribe(Mongo::Monitoring::COMMAND, subscriber)
    end

    @actual_count = subscriber.find_count
    @actual_count == @expected_count
  end

  failure_message do
    "expected #{@collection_name} to be queried #{@expected_count} time(s), but was queried #{@actual_count} time(s)"
  end

  class QueryCountSubscriber
    attr_reader :find_count

    def initialize(collection_name)
      @collection_name = collection_name
      @find_count = 0
    end

    def started(event)
      return unless event.command_name == "find"
      return unless event.command["find"] == @collection_name
      @find_count += 1
    end

    def succeeded(_); end
    def failed(_); end
  end
end
