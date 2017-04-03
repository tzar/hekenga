require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Open a pry session preloaded with this library"
task :console do
  sh "bin/console", verbose: false
end

task :default => :spec
