module RBS
  def self.version
    Gem::Version.new File.read(File.expand_path('../../../VERSION', __FILE__))
  end

  module VERSION
    MAJOR, MINOR, TINY, PRE = RBS.version.segments
    STRING = RBS.version.to_s
  end
end
