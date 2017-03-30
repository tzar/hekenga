module Hekenga
  class Config
    attr_accessor :dir, :root, :report_sleep
    def initialize
      @report_sleep = 10
      @root         = Dir.pwd
      @dir          = ["db", "hekenga"]
    end
    def abs_dir
      File.join(@root, *[@dir].flatten)
    end
  end
end
