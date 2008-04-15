require 'test/unit'
require 'rubygems'
require 'rubygems/test_utilities'
require 'test/zentest_assertions'
require 'rc_rest/net_http_stub'
require 'rc_rest/uri_stub'

$TESTING = true

require 'tinderbox/gem_tinderbox'
require 'tinderbox/gem_runner'

class Firebrigade::Cache
  attr_reader :builds, :owners, :projects, :versions, :targets
end

class Tinderbox::GemTinderbox
  attr_writer :source_info_cache, :target_id
  attr_reader :fc, :seen_gem_names
end

class TestTinderboxGemTinderbox < Test::Unit::TestCase

  def setup
    Net::HTTP.params = []
    Net::HTTP.paths = []
    Net::HTTP.responses = []

    URI::HTTP.uris = []
    URI::HTTP.responses = []

    @root = File.join Dir.tmpdir, "tinderbox_test_#{$$}"
    @sandbox_dir = File.join @root, 'sandbox'

    Gem.configuration.verbose = false # HACK resets Gem.sources
    ENV['GEM_HOME'] = @sandbox_dir
    Gem.clear_paths
    Gem::SourceInfoCache.reset

    @gem_repo = 'http://gems.example.com/'
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher
    Gem.sources.replace [@gem_repo]

    @tgt = Tinderbox::GemTinderbox.new 'firebrigade.example.com', 'username',
                                       'password'

    @spec = Gem::Specification.new
    @spec.name = 'gem_one'
    @spec.version = '0.0.2'
    @spec.rubyforge_project = 'gem'

    @source_index = Gem::SourceIndex.new
    @source_index.add_spec @spec

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] =
      Marshal.dump @source_index
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

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    util_test_run_error "Gem::RemoteFetcher::FetchError"
  end

  def test_run_remote_source_exception
    Net::HTTP.responses << proc do |req|
      raise Gem::RemoteSourceException, 'HTTP Response 403'
    end

    util_test_run_error 'HTTP Response 403'
  end

  def test_run_spec
    fc = util_setup_cache
    def fc.get_build_id(*a) nil end # not tested

    Net::HTTP.responses << <<-EOF
<ok>
  <build>
    <id>5</id>
    <created_on>#{Time.now}</created_on>
    <duration>1.5</duration>
    <successful>true</successful>
    <target_id>4</target_id>
    <version_id>3</version_id>
  </build>
</ok>
    EOF

    build = nil

    out, err = util_capture do
      build = @tgt.run_spec @spec
    end

    assert_equal '', out.read
    err = err.read.split "\n"
    assert_equal "*** Checking #{@spec.full_name}", err.shift
    assert_equal "*** Igniting (http://firebrigade.example.com/gem/show/gem_one/0.0.2)", err.shift
    assert_equal "*** I lit #{@spec.full_name} on fire!", err.shift
    assert_empty err
  end

  def test_run_spec_install_error
    fc = util_setup_cache
    def fc.get_build_id(*a) nil end # not tested
    def @tgt.test_gem(spec) raise Tinderbox::InstallError end
    @tgt.seen_gem_names << @spec

    out, err = util_capture do
      @tgt.run_spec @spec
    end

    deny_includes @spec.full_name, @tgt.seen_gem_names
    assert_equal '', out.read
    err = err.read.split "\n"
    assert_equal "*** Checking #{@spec.full_name}", err.shift
    assert_equal "*** Igniting (http://firebrigade.example.com/gem/show/gem_one/0.0.2)", err.shift
    assert_equal "*** Failed to install (Tinderbox::InstallError)", err.shift
    assert_empty err
  end

  def test_run_spec_manual_install_error
    fc = util_setup_cache
    def fc.get_build_id(*a) nil end # not tested
    def @tgt.test_gem(spec) raise Tinderbox::ManualInstallError end
    @tgt.seen_gem_names << @spec

    out, err = util_capture do
      @tgt.run_spec @spec
    end

    assert_includes @spec, @tgt.seen_gem_names
    assert_equal '', out.read
    err = err.read.split "\n"
    assert_equal "*** Checking #{@spec.full_name}", err.shift
    assert_equal "*** Igniting (http://firebrigade.example.com/gem/show/gem_one/0.0.2)",
                 err.shift
    assert_equal "*** Failed to install (Tinderbox::ManualInstallError)",
                 err.shift
    assert_empty err
  end

  def test_run_spec_tested
    fc = util_setup_cache
    def fc.get_build_id(*a) true end # tested

    out, err = util_capture do
      @tgt.run_spec @spec
    end

    assert_equal '', out.read
    err = err.read.split "\n"
    assert_equal "*** Checking #{@spec.full_name}", err.shift
    assert_empty err
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
    def o.refresh(arg = nil) @refreshed = true end

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

  def util_setup_cache
    @tgt.target_id = 5
    fc = @tgt.fc
    fc.owners['gem'] = 100
    fc.projects[[100, 'gem_one']] = 101
    fc.versions[[101, '0.0.2']] = 102
    
    fc
  end

end

