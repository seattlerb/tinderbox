require 'test/unit'
require 'rubygems/version'
require 'rubygems/rubygems_version'
require 'tinderbox/gem_runner'

class TestSanity < Test::Unit::TestCase

  def test_rubygems_version
    rubygems_version = Gem::Version.new Gem::RubyGemsVersion
    required_version = Gem::Version.new '0.9.1'

    assert_operator required_version, :<=, rubygems_version
  end

  def test_testrb_exists
    runner = Tinderbox::GemRunner.new nil, nil
    assert File.exist?(runner.testrb)
  end

end

