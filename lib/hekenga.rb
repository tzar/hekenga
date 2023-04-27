require "mongoid"
require "hekenga/version"
require "hekenga/migration"
require "hekenga/dsl"
require "hekenga/config"
require "hekenga/irreversible"
require "hekenga/virtual_method"
require "hekenga/scaffold"

module Hekenga
  @@load_all_mutex = Mutex.new
  @@registry_mutex = Mutex.new
  @@registry       = []

  class << self
    def configure
      yield(config)
    end

    def config
      @config ||= Hekenga::Config.new
    end

    def load_all!
      return if @loaded

      @@load_all_mutex.synchronize do
        Dir.glob(File.join(config.abs_dir, "*.rb")).each do |path|
          require path
        end

        @loaded = true
      end
    end

    def migration(&block)
      Hekenga::DSL::Migration.new(&block).object.tap do |obj|
        @@registry_mutex.synchronize { registry.push(obj) }
      end
    end

    def find_migration(key)
      load_all!
      registry.detect do |migration|
        migration.to_key == key
      end
    end

    def registry
      @@registry
    end

    def reset_registry
      @@registry_mutex.synchronize { @@registry = [] }
    end

    def status(migration)
      logs = Hekenga::Log.where(
        pkey: migration.to_key
      ).to_a
      return :naught if logs.empty?
      return :skipped if logs.any? {|x| x.skip}
      return :failed if logs.any? {|x| x.cancel}
      return :complete if logs.all? {|x| x.done} && logs.length == migration.tasks.length
      return :running
    end

    def log(str)
      print str.to_s+"\n"
    end
  end
end
