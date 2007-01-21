require 'test/unit'

require 'rubygems'
require 'test/zentest_assertions'

require 'rbconfig'
require 'tmpdir'

require 'tinderbox/gem_runner'

class Tinderbox::GemRunner
  attr_writer :gemspec
  attr_accessor :installed_gems, :remote_installer, :log
  attr_reader :duration, :successful
end

class Gem::RemoteInstaller
  alias orig_install install
  def install(gem_name, version = '1.2.3')
    full_gem_name = "#{gem_name}-#{version}"
    gem_path = File.join Gem.dir, 'gems', full_gem_name
    FileUtils.mkpath gem_path
    s = Gem::Specification.new
    s.name = gem_name
    s.version = version
    s.loaded_from = File.join Gem.dir, 'gems', full_gem_name
    return [s]
  end
end

class Gem::SourceInfoCache
  attr_writer :cache_data
  class << self; attr_writer :cache; end
end

class TestTinderboxGemRunner < Test::Unit::TestCase

  def setup
    @gem_name = 'some_test_gem'
    @gem_version = '1.2.3'
    @gem_full_name = "#{@gem_name}-#{@gem_version}"

    @rake = Gem::Specification.new
    @rake.name = 'rake'
    @rake.version = '999.999.999'

    @rspec = Gem::Specification.new
    @rspec.name = 'rspec'
    @rspec.version = '999.999.999'

    @gemspec = Gem::Specification.new
    @gemspec.name = @gem_name
    @gemspec.version = @gem_version
    @gemspec.loaded_from = File.join Gem.dir, 'gems', @gem_full_name
    @gemspec.require_paths = ['lib', 'other']

    @root = File.join Dir.tmpdir, 'tinderbox_test'
    @sandbox_dir = File.join @root, 'sandbox'
    @tgr = Tinderbox::GemRunner.new @gem_name, @gem_version, @root

    @util_test_setup = false
  end

  def teardown
    FileUtils.remove_dir @root rescue nil
    ENV['GEM_HOME'] = nil
    Gem.clear_paths
  end

  def test_gem_lib_paths
    @tgr.gemspec = @gemspec
    assert_equal "lib#{Config::CONFIG['PATH_SEPARATOR']}other",
                 @tgr.gem_lib_paths
  end

  def test_initialize
    assert_equal @sandbox_dir, @tgr.sandbox_dir
    assert_equal File.join(Config::CONFIG['libdir'], 'ruby', 'gems',
                           Config::CONFIG['ruby_version']),
                 @tgr.host_gem_dir
    assert_equal @gem_name, @tgr.gem_name
    assert_equal @gem_version, @tgr.gem_version
    assert_equal nil, @tgr.gemspec

    e = assert_raise ArgumentError do
      tgr = Tinderbox::GemRunner.new @gem_name, @gem_version, 'relative'
    end

    assert_equal 'root must not be relative', e.message
  end

  def test_install
    @tgr.sandbox_setup
    @tgr.install_sources
    @tgr.install

    deny_empty Dir[File.join(@sandbox_dir, 'gems', @gem_full_name)]
    assert_equal true, File.directory?(File.join(@root, 'cache'))
    assert_equal @gem_full_name, @tgr.gemspec.full_name
  end

  def test_install_bad_gem
    ri = @tgr.remote_installer
    def ri.install(*a) raise Gem::InstallError end

    @tgr.sandbox_setup
    @tgr.install_sources
    assert_raise Tinderbox::InstallError do
      @tgr.install
    end

    assert_empty Dir[File.join(@sandbox_dir, 'gems', @gem_full_name)]
  end

  def test_install_ext_build_error
    ri = @tgr.remote_installer
    def ri.install(*a) raise Gem::Installer::ExtensionBuildError end

    @tgr.sandbox_setup
    @tgr.install_sources
    assert_raise Tinderbox::BuildError do
      @tgr.install
    end

    assert_empty Dir[File.join(@sandbox_dir, 'gems', @gem_full_name)]
  end

  def test_install_wrong_platform
    ri = @tgr.remote_installer
    def ri.install(*a) raise Gem::RemoteInstallationCancelled end

    @tgr.sandbox_setup
    @tgr.install_sources

    assert_raise Tinderbox::ManualInstallError do
      @tgr.install
    end
  end

  def test_install_rake
    o = Object.new
    def o.search(pattern)
      rake = Gem::Specification.new
      rake.name = 'rake'
      rake.version = '999.999.999'
      rake
    end
    sic = Gem::SourceInfoCache.new
    sic_e = Gem::SourceInfoCacheEntry.new o, 0
    sic.cache_data = { 'foo' => sic_e }
    Gem::SourceInfoCache.cache = sic

    @tgr.sandbox_setup
    @tgr.installed_gems = []
    @tgr.install_sources
    log = @tgr.install_rake

    deny_empty Dir[File.join(@sandbox_dir, 'gems', 'rake-*')]

    expected = <<-EOF
!!! HAS Rakefile, DOES NOT DEPEND ON RAKE!  NEEDS s.add_dependency 'rake'
### rake installed, even though you claim not to need it
    EOF

    assert_equal expected, log
  ensure
    Gem::SourceInfoCache.instance_variable_set :@cache, nil
  end

  def test_install_rspec
    o = Object.new
    def o.search(pattern)
      rake = Gem::Specification.new
      rake.name = 'rspec'
      rake.version = '999.999.999'
      rake
    end
    sic = Gem::SourceInfoCache.new
    sic_e = Gem::SourceInfoCacheEntry.new o, 0
    sic.cache_data = { 'foo' => sic_e }
    Gem::SourceInfoCache.cache = sic

    @tgr.sandbox_setup
    @tgr.installed_gems = []
    @tgr.install_sources
    log = @tgr.install_rspec 'message'

    deny_empty Dir[File.join(@sandbox_dir, 'gems', 'rspec-*')]

    expected = <<-EOF
!!! HAS message, DOES NOT DEPEND ON RSPEC!  NEEDS s.add_dependency 'rspec'
### RSpec installed, even though you claim not to need it
    EOF

    assert_equal expected, log
  ensure
    Gem::SourceInfoCache.instance_variable_set :@cache, nil
  end

  def test_install_sources
    @tgr.sandbox_setup
    @tgr.install_sources

    assert_equal true, File.exist?(File.join(@sandbox_dir, 'source_cache'))
    deny_empty Dir["#{File.join @sandbox_dir, 'gems', 'sources'}-*"]
  end

  def test_passed_eh
    status = Object.new
    def status.exitstatus() 0; end

    log = ""
    tested = @tgr.passed? status

    assert_equal "", @tgr.log

    deny tested
    deny @tgr.successful
  end

  def test_passed_eh_spec
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "1 specification, 0 failures\n"
    tested = @tgr.passed? status

    assert_equal "1 specification, 0 failures\n", @tgr.log

    assert tested
    assert @tgr.successful
  end

  def test_passed_eh_spec_broken
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "1 specification, 1 failure\n"
    tested = @tgr.passed? status

    expected = <<-EOF
1 specification, 1 failure
!!! Project has broken spec target, exited with 0 after spec failure
    EOF

    assert_equal expected, @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_passed_eh_spec_exit_failed
    status = Object.new
    def status.exitstatus() 1; end

    @tgr.log = "1 specification, 0 failures\n"
    tested = @tgr.passed? status
    assert_equal "1 specification, 0 failures\n", @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_passed_eh_spec_no_assertions
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "0 specifications, 0 failures\n"
    tested = @tgr.passed? status

    expected = <<-EOF
0 specifications, 0 failures
!!! No output indicating success found
    EOF

    assert_equal expected, @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_passed_eh_test
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "1 tests, 1 assertions, 0 failures, 0 errors\n"
    tested = @tgr.passed? status

    assert_equal "1 tests, 1 assertions, 0 failures, 0 errors\n", @tgr.log

    assert tested
    assert @tgr.successful
  end

  def test_passed_eh_test_broken
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "1 tests, 1 assertions, 1 failures, 0 errors\n"
    tested = @tgr.passed? status

    expected = <<-EOF
1 tests, 1 assertions, 1 failures, 0 errors
!!! Project has broken test target, exited with 0 after test failure
    EOF

    assert_equal expected, @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_passed_eh_test_exit_failed
    status = Object.new
    def status.exitstatus() 1; end

    @tgr.log = "1 tests, 1 assertions, 0 failures, 0 errors\n"
    tested = @tgr.passed? status
    assert_equal "1 tests, 1 assertions, 0 failures, 0 errors\n", @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_passed_eh_test_no_assertions
    status = Object.new
    def status.exitstatus() 0; end

    @tgr.log = "1 tests, 0 assertions, 0 failures, 0 errors\n"
    tested = @tgr.passed? status

    expected = <<-EOF
1 tests, 0 assertions, 0 failures, 0 errors
!!! No output indicating success found
    EOF

    assert_equal expected, @tgr.log

    assert tested
    deny @tgr.successful
  end

  def test_rake_installed_eh
    e = assert_raises RuntimeError do
      @tgr.rake_installed?
    end

    assert_equal 'you haven\'t installed anything yet', e.message

    @tgr.installed_gems = []

    assert_equal false, @tgr.rake_installed?

    @tgr.installed_gems = [@rake]

    assert_equal true, @tgr.rake_installed?
  end

  def test_rspec_installed_eh
    e = assert_raises RuntimeError do
      @tgr.rspec_installed?
    end

    assert_equal 'you haven\'t installed anything yet', e.message

    @tgr.installed_gems = []

    assert_equal false, @tgr.rspec_installed?

    @tgr.installed_gems = [@rspec]

    assert_equal true, @tgr.rspec_installed?
  end

  def test_ruby # HACK lame
    ruby_exe = Config::CONFIG['ruby_install_name'] + Config::CONFIG['EXEEXT']
    ruby = File.join Config::CONFIG['bindir'], ruby_exe

    assert_equal ruby, @tgr.ruby
  end

  def test_run
    build = @tgr.run

    assert_equal true, File.exist?(File.join(@sandbox_dir, 'source_cache'))

    assert_equal 0, build.duration
    assert_equal false, build.successful

    expected = <<-EOF.strip
### installing some_test_gem-1.2.3 + dependencies
### some_test_gem-1.2.3
### testing some_test_gem-1.2.3
!!! could not figure out how to test some_test_gem-1.2.3
    EOF

    assert_equal expected, build.log
  end

  def test_run_command
    tested = @tgr.run_command "ruby -e '$stderr.puts \"bye\"; $stdout.puts \"hi\"'"

    expected = <<-EOF
### ruby -e '$stderr.puts \"bye\"; $stdout.puts \"hi\"'
bye
hi
    EOF

    assert_equal expected, @tgr.log
    assert_operator 0, :<, @tgr.duration
    deny tested
  end

  def test_run_command_tested
    tested = @tgr.run_command "ruby -e \"puts '1 specification, 1 failure'\""

    assert tested, @tgr.log
  end

  def test_sandbox_cleanup
    FileUtils.mkpath @sandbox_dir

    assert_equal true, File.exist?(@sandbox_dir)

    @tgr.sandbox_cleanup

    assert_equal false, File.exist?(@sandbox_dir)
  end

  def test_sandbox_cleanup_no_dir
    assert_equal false, File.exist?(@sandbox_dir)

    @tgr.sandbox_cleanup

    assert_equal false, File.exist?(@sandbox_dir)
  end

  def test_sandbox_setup
    @tgr.sandbox_setup

    assert_equal true, File.exist?(@sandbox_dir)
    assert_equal true, File.exist?(File.join(@sandbox_dir, 'gems'))
    assert_equal @sandbox_dir, ENV['GEM_HOME']
    assert_equal @sandbox_dir, Gem.dir

    e = assert_raise RuntimeError do
      @tgr.sandbox_setup
    end

    assert_equal "#{@sandbox_dir} already exists", e.message
  end

  def test_test_best_effort
    util_test_setup

    File.open File.join(@gemspec.full_gem_path, 'Rakefile'), 'w' do |fp|
      fp.write <<-EOF
require 'rake/testtask'

task :test do exit 1 end
      EOF
    end

    File.open File.join(@gemspec.full_gem_path, 'Makefile'), 'w' do |fp|
      fp.write <<-EOF
test:
\texit 1

.PHONY: test
      EOF
    end

    util_test_assertions :test, true, -1
  end

  def test_test_no_tests
    util_test_setup

    @tgr.gemspec = @gemspec
    @tgr.test

    assert_equal 0, @tgr.duration
    assert_equal false, @tgr.successful

    expected = <<-EOF.strip
!!! could not figure out how to test some_test_gem-1.2.3
    EOF

    assert_equal expected, @tgr.log
  end

  def test_test_Makefile_fail
    util_test_add_Makefile
    util_test_assertions :test, false, -2
  end

  def test_test_Makefile_pass
    util_test_add_Makefile
    util_test_assertions :test, true, -1
  end

  def test_test_Rakefile_spec_fail
    util_test_add_Rakefile :spec
    util_test_assertions :spec, false, -1
  end

  def test_test_Rakefile_spec_pass
    util_test_add_Rakefile :spec
    util_test_assertions :spec, true, -1
  end

  def test_test_Rakefile_test_fail
    util_test_add_Rakefile
    util_test_assertions :test, false, -1
  end

  def test_test_Rakefile_test_pass
    util_test_add_Rakefile
    util_test_assertions :test, true, -1
  end

  def test_test_testrb_fail
    util_test_assertions :test, false, -1
  end

  def test_test_testrb_pass
    util_test_assertions :test, true, -1

    assert_equal "### #{@tgr.ruby} -Ilib:other -S #{@tgr.testrb} test",
                 @tgr.log.split("\n").first
  end

  def test_test_spec_fail
    util_test_assertions :spec, false, -1
  end

  def test_test_spec_pass
    util_test_assertions :spec, true, -1
  end

  def test_testrb # HACK lame
    testrb_exe = 'testrb' + (RUBY_PLATFORM =~ /mswin/ ? '.bat' : '')
    testrb = File.join Config::CONFIG['bindir'], testrb_exe

    assert_equal testrb, @tgr.testrb
  end

  def util_test_add_Makefile
    util_test_setup
    File.open File.join(@gemspec.full_gem_path, 'Makefile'), 'w' do |fp|
      fp.write <<-EOF
test:
\ttestrb test

.PHONY: test
      EOF
    end
  end

  def util_test_add_Rakefile(type = :test)
    util_test_setup
    File.open File.join(@gemspec.full_gem_path, 'Rakefile'), 'w' do |fp|
      fp.write <<-EOF
require 'rake/testtask'
require 'spec/rake/spectask

EOF

      case type
      when :test then
        fp.write <<-EOF
Rake::TestTask.new :test do |t|
  t.test_files = FileList['test/test_*.rb']
end
        EOF
      when :spec then
        fp.write <<-EOF
Spec::Rake::SpecTask.new
        EOF
      else
        raise ArgumentError, "unknown type #{type.inspect}"
      end
    end
  end

  def util_test_add_test(passes)
    test_dir = File.join @gemspec.full_gem_path, 'test'
    @test_file = File.join test_dir, 'test_something.rb'
    FileUtils.mkpath test_dir

    File.open @test_file, 'w' do |fp|
      fp.write <<-EOF
require 'test/unit'

class TestSomething < Test::Unit::TestCase
  def test_something
    assert #{passes}
  end
end
      EOF
    end
  end

  def util_test_add_spec(passes)
    test_dir = File.join @gemspec.full_gem_path, 'spec'
    @spec_file = File.join test_dir, 'true_spec.rb'
    FileUtils.mkpath test_dir

    File.open @spec_file, 'w' do |fp|
      fp.write <<-EOF
context "dummy spec" do
  specify "should be true" do
    #{passes}.should == true
  end
end
      EOF
    end
  end

  def util_test_assertions(type, passes, count_index)
    util_test_setup
    case type
    when :test then util_test_add_test passes
    when :spec then util_test_add_spec passes
    else raise ArgumentError, "unknown test type #{type.inspect}"
    end

    @tgr.gemspec = @gemspec

    ENV['GEM_HOME'] = nil
    successful = @tgr.test

    assert_operator 0, :<, @tgr.duration, 'Time taken too short'
    assert_equal passes, @tgr.successful, 'The tests failed'

    log = @tgr.log.split "\n"

    failures = passes ? 0 : 1

    expected = case type
               when :test then
                 "1 tests, 1 assertions, #{failures} failures, 0 errors"
               when :spec then
                 "1 specification, #{failures} failure#{passes ? 's' : ''}"
               end

    #log.each_with_index do |l, i| puts "#{i}\t#{l[0..10]}" end
    assert_equal expected, log[count_index]
  end

  def util_test_setup
    return if @util_test_setup
    @util_test_setup = true
    @tgr.installed_gems = [@rake]

    ENV['GEM_HOME'] = @sandbox_dir
    Gem.clear_paths
    @gemspec.loaded_from = File.join Gem.dir, 'gems', @gem_full_name
    FileUtils.mkpath @gemspec.full_gem_path
  end

end

