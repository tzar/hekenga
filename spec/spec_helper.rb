$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

# Models to test against in spec
MODELS = File.join(File.dirname(__FILE__), "models")

require "pry"
require "database_cleaner"
require "hekenga"

Dir["#{MODELS}/*.rb"].each {|f| require f}

Mongoid.configure do |config|
  config.connect_to "hekenga_test"
  config.logger = nil
end
Hekenga.configure do |config|
  config.report_sleep = 1
end
Mongo::Logger.level = ::Logger::FATAL
DatabaseCleaner.orm = "mongoid"
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
