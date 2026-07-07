$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

# Models to test against in spec
MODELS = File.join(File.dirname(__FILE__), "models")

require "pry"
require "database_cleaner-mongoid"
require "hekenga"

Dir["#{MODELS}/*.rb"].each {|f| require f}
Dir[File.join(File.dirname(__FILE__), "support", "*.rb")].each {|f| require f}

Mongoid.configure do |config|
  config.clients.default = {
    hosts: [ENV.fetch("MONGO_HOST", "localhost:27017")],
    database: "hekenga_test",
    options: {
      # The test cluster (see docker-compose.yml) is a single-member replica
      # set advertising itself as "localhost:27017". We must let the driver
      # perform replica-set topology discovery (i.e. NOT set direct_connection)
      # so that Cluster#replica_set? is true and transactions are permitted.
      replica_set: "rs0"
    }
  }
  config.logger = nil
end
Hekenga.configure do |config|
  config.report_sleep = 1
end
Mongo::Logger.level = ::Logger::FATAL
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = nil

RSpec.configure do |config|
  config.before(:all) do
    Hekenga::Log.all.delete_all
    Hekenga::Failure.all.delete_all
    Example.all.delete_all
  end
  config.before(:each) do
    DatabaseCleaner.start
    Hekenga.reset_registry
  end
  config.after(:each) do
    DatabaseCleaner.clean
    Hekenga.reset_registry
  end
  config.after(:all) do
    DatabaseCleaner.clean
    Hekenga.reset_registry
  end
end
