require 'test/unit'
require 'rubygems'
require 'tinderbox/gem_runner'

class TestSanity < Test::Unit::TestCase

  def test_rubygems_version
    rubygems_version = Gem::Version.new Gem::RubyGemsVersion
    required_version = Tinderbox::GemRunner::REQUIRED_RUBYGEMS_VERSION

    assert required_version.satisfied_by?(rubygems_version),
           "RubyGems #{rubygems_version} is too old, need #{required_version}"
  end

  def test_testrb_exists
    runner = Tinderbox::GemRunner.new nil, nil
    assert File.exist?(runner.testrb),
           "Could not find testrb at #{runner.testrb}"
  end

end

