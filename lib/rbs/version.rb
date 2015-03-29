module RBS
  def self.version
    Gem::Version.new(File.read(File.expand_path('../../../VERSION', __FILE__)))
  end

  def self.version_string
    "rbs v#{version}"
  end

  module VERSION
    MAJOR, MINOR, TINY, PRE = RBS.version.segments
    STRING = RBS.version.to_s
  end
end
