require 'hekenga/migration'
module Hekenga
  class Scaffold
    def initialize(description)
      @migration = Hekenga::Migration.new.tap do |migration|
        migration.description = description
        migration.stamp       = Time.now
      end
    end

    def write!
      if File.exist?(to_path)
        raise "That migration already exists!"
      end
      File.open(to_path, "w") {|f| f.puts self }
    end

    def to_path
      @path ||= File.join(Hekenga.config.abs_dir, @migration.to_key.gsub(/\:/, '-') +
        '.rb')
    end

    def to_s
      <<-EOF.strip_heredoc
      Hekenga.migration do
        ## Required
        description #{@migration.description.inspect}
        created #{@migration.timestamp.sub("T", " ").inspect}

        ## Optional
        # batch_size 10

        ## Simple tasks
        # task "task description" do
        #   up do
        #   end
        # end

        ## Per document tasks
        # per_document "task description" do
        #   ## Required
        #   scope MyModel.all
        #
        #   ## Optional config
        #   # parallel!
        #   # timeless!
        #   # skip_prepare!
        #   # when_invalid :prompt # :prompt, :cancel, :stop, :continue
        #   #
        #   # setup do
        #   # end
        #   # filter do
        #   # end
        #
        #   up do |doc|
        #   end
        # end
      end
      EOF
    end

  end
end
