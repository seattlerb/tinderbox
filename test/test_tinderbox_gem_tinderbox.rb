require 'test/unit'
require 'rubygems'
require 'test/zentest_assertions'
require 'rc_rest/net_http_stub'
require 'rc_rest/uri_stub'

$TESTING = true

require 'tinderbox/gem_tinderbox'
require 'tinderbox/gem_runner'

class Firebrigade::Cache
  attr_reader :builds
end

class Tinderbox::GemTinderbox
  attr_writer :source_info_cache, :target_id
  attr_reader :fc
end

class TestTinderboxGemTinderbox < Test::Unit::TestCase

  def setup
    Net::HTTP.params = []
    Net::HTTP.paths = []
    Net::HTTP.responses = []

    URI::HTTP.uris = []
    URI::HTTP.responses = []

    @tgt = Tinderbox::GemTinderbox.new 'firebrigade.example.com', 'username',
                                       'password'

    sic = {}
    def sic.refresh
    end

    def sic.cache_data
      o = Object.new
      def o.each(&block)
        spec = Gem::Specification.new
        spec.name = 'gem_one'
        spec.version = '0.0.2'
        si = Gem::SourceIndex.new 'gem_one-0.0.2' => spec
        sic_e = Gem::SourceInfoCacheEntry.new si, 0
        yield 'http://gems.example.com', sic_e
      end
      o
    end

    @tgt.source_info_cache = sic

    @spec = Gem::Specification.new
    @spec.name = 'gem_one'
    @spec.version = '0.0.2'
    @spec.rubyforge_project = 'gem'
  end

  def test_new_gems
    specs = @tgt.new_gems.map { |s| s.full_name }
    assert_equal ['gem_one-0.0.2'], specs
    specs = @tgt.new_gems.map { |s| s.full_name }
    assert_equal [], specs, 'Your rubygems needs Gem::Specification#eql?'
  end

  def test_run_communication_error
    Net::HTTP.responses << proc do |req|
      raise Errno::ECONNREFUSED, 'connect(2)'
    end

    util_test_run_error "Communication error: Connection refused - connect(2)(Errno::ECONNREFUSED)"
  end

  def test_run_fetch_error
    Net::HTTP.responses << <<-EOF
<ok>
  <target>
    <id>5</id>
    <platform>fake platform</platform>
    <release_date>fake release_date</release_date>
    <username>fake username</username>
    <version>fake version</version>
  </target>
</ok>
    EOF

    o = Object.new
    def o.refresh() raise Gem::RemoteFetcher::FetchError end
    @tgt.instance_variable_set :@source_info_cache, o

    util_test_run_error "Gem::RemoteFetcher::FetchError"
  end

  def test_tested_eh
    @tgt.target_id = 5
    @tgt.fc.builds[[3, 5]] = 4
    assert_equal true, @tgt.tested?(3)

    URI::HTTP.responses << <<-EOF
<error>
  <message>No such build exists</message>
</error>
    EOF

    assert_equal false, @tgt.tested?(-1)
  end

  def test_update_gems
    o = Object.new
    def o.refreshed?() @refreshed end
    def o.refresh() @refreshed = true end

    @tgt.instance_variable_set :@source_info_cache, o

    @tgt.update_gems

    assert_equal true, o.refreshed?
  end

  def util_test_run_error(message)
    out, err = util_capture do
      @tgt.run
    end

    assert_equal '', out.read

    err = err.read.split "\n"
    assert_equal message, err.first
    assert_match(/Will retry at/, err.last)
  end

end

