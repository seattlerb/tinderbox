require 'tinderbox'

require 'English'
require 'fileutils'
require 'open-uri'
require 'rbconfig'
require 'stringio'
require 'timeout'

require 'rubygems'
require 'rubygems/remote_installer'

##
# Tinderbox::GemRunner tests a gem and creates a Tinderbox::Build holding the
# results of the test run.
#
# You can use tinderbox_gem_build to test your gem in a sandbox.

class Tinderbox::GemRunner

  ##
  # Raised when the tinderbox job times out.

  class RunTimeout < Timeout::Error; end

  ##
  # Sandbox directory for rubygems

  attr_reader :sandbox_dir

  ##
  # Host's gem repository directory

  attr_reader :host_gem_dir

  ##
  # Name of the gem to test

  attr_reader :gem_name

  ##
  # Version of the gem to test

  attr_reader :gem_version

  ##
  # Gemspec of the gem to test

  attr_reader :gemspec

  ##
  # Maximum time to wait for run_command to complete

  attr_accessor :timeout

  ##
  # Creates a new GemRunner that will test the latest gem named +gem+ using
  # +root+ for the sandbox.  If no +root+ is given, ./tinderbox is used for
  # the sandbox.

  def initialize(gem_name, gem_version, root = nil)
    root = File.join Dir.pwd, 'tinderbox' if root.nil?
    raise ArgumentError, 'root must not be relative' unless root[0] == ?/
    @sandbox_dir = File.expand_path File.join(root, 'sandbox')
    @cache_dir = File.expand_path File.join(root, 'cache')
    FileUtils.mkpath @cache_dir unless File.exist? @cache_dir

    ENV['GEM_HOME'] = nil
    Gem.clear_paths

    @host_gem_dir = Gem.dir
    @host_gem_source_index = Gem::SourceInfoCache.new.cache_file
    @gem_name = gem_name
    @gem_version = gem_version

    @remote_installer = Gem::RemoteInstaller.new :include_dependencies => true,
                                                 :cache_dir => @cache_dir,
                                                 :wrappers => true
    @remote_installer.ui = Gem::SilentUI.new
    @gemspec = nil
    @installed_gems = nil

    @timeout = 120

    @log = ''
    @duration = 0
    @successful = :not_tested
  end

  ##
  # The gem's library paths.

  def gem_lib_paths
    @gemspec.require_paths.join Config::CONFIG['PATH_SEPARATOR']
  end

  ##
  # Install the gem into the sandbox.

  def install
    retries = 5

    begin
      @installed_gems = @remote_installer.install @gem_name, @gem_version
      @gemspec = @installed_gems.first
      "### #{@installed_gems.map { |s| s.full_name }.join "\n### "}"
    rescue Gem::RemoteInstallationCancelled => e
      raise Tinderbox::ManualInstallError,
            "Installation of #{@gem_name}-#{@gem_version} requires manual intervention"
    rescue Gem::Installer::ExtensionBuildError => e
      raise Tinderbox::BuildError, "Unable to build #{@gem_name}-#{@gem_version}:\n\n#{e.message}"
    rescue Gem::InstallError, Gem::GemNotFoundException => e
      FileUtils.rm_rf File.join(@cache_dir, "#{@gem_name}-#{@gem_version}.gem")
      raise Tinderbox::InstallError,
            "Installation of #{@gem_name}-#{@gem_version} failed (#{e.class}):\n\n#{e.message}"
    rescue SystemCallError => e # HACK push into Rubygems
      retries -= 1
      retry if retries >= 0
      raise Tinderbox::InstallError,
            "Installation of #{@gem_name}-#{@gem_version} failed after 5 tries"
    rescue OpenURI::HTTPError => e # HACK push into Rubygems
      raise Tinderbox::InstallError,
            "Could not download #{@gem_name}-#{@gem_version}"
    rescue SystemStackError => e
      raise Tinderbox::InstallError,
            "Installation of #{@gem_name}-#{@gem_version} caused an infinite loop:\n\n\t#{e.backtrace.join "\n\t"}"
    end
  end

  ##
  # Installs the rake gem into the sandbox

  def install_rake
    log = []
    log << "!!! HAS Rakefile, DOES NOT DEPEND ON RAKE!  NEEDS s.add_dependency 'rake'"

    retries = 5

    rake_version = Gem::SourceInfoCache.search('rake').last.version.to_s

    begin
      @installed_gems.push(*@remote_installer.install('rake', rake_version))
      log << "### rake installed, even though you claim not to need it"
    rescue Gem::InstallError, Gem::GemNotFoundException => e
      log << "Installation of rake failed (#{e.class}):\n\n#{e.message}"
    rescue SystemCallError => e
      retries -= 1
      retry if retries >= 0
      log << "Installation of rake failed after 5 tries"
    rescue OpenURI::HTTPError => e
      log << "Could not download rake"
    end

    @log << (log.join("\n") + "\n")
  end

  ##
  # Installs the RSpec gem into the sandbox

  def install_rspec(message)
    log = []
    log << "!!! HAS #{message}, DOES NOT DEPEND ON RSPEC!  NEEDS s.add_dependency 'rspec'"

    retries = 5

    rspec_version = Gem::SourceInfoCache.search(/^rspec$/).last.version.to_s

    begin
      @installed_gems.push(*@remote_installer.install('rspec', rspec_version))
      log << "### RSpec installed, even though you claim not to need it"
    rescue Gem::InstallError, Gem::GemNotFoundException => e
      log << "Installation of RSpec failed (#{e.class}):\n\n#{e.message}"
    rescue SystemCallError => e
      retries -= 1
      retry if retries >= 0
      log << "Installation of RSpec failed after 5 tries"
    rescue OpenURI::HTTPError => e
      log << "Could not download rspec"
    end

    @log << (log.join("\n") + "\n")
  end

  ##
  # Checks to see if #process_status exited successfully, ran at least one
  # assertion or specification and the run finished without error or failure.

  def passed?(process_status)
    tested = @log =~ /^\d+ tests, \d+ assertions, \d+ failures, \d+ errors$/ ||
             @log =~ /^\d+ (specification|example)s?, \d+ failures?$/
    @successful = process_status.exitstatus == 0

    if not tested and @successful then
      @successful = false
      return tested
    end

    if @log =~ / (\d+) failures, (\d+) errors/ and ($1 != '0' or $2 != '0') then
      @log << "!!! Project has broken test target, exited with 0 after test failure\n" if @successful
      @successful = false
    elsif @log =~ /\d+ specifications?, (\d+) failures?$/ and $1 != '0' then
      @log << "!!! Project has broken spec target, exited with 0 after spec failure\n" if @successful
      @successful = false
    elsif (@log =~ / 0 assertions/ or @log !~ / \d+ assertions/) and
          (@log =~ /0 (specification|example)s/ or # HACK /^0 ?
           @log !~ /\d+ (specification|example)/) then
      @successful = false
      @log << "!!! No output indicating success found\n"
    end

    return tested
  end

  ##
  # Checks to see if the rake gem was installed by the gem under test

  def rake_installed?
    raise 'you haven\'t installed anything yet' if @installed_gems.nil?
    @installed_gems.any? { |s| s.name == 'rake' }
  end

  ##
  # Checks to see if the rspec gem was installed by the gem under test

  def rspec_installed?
    raise 'you haven\'t installed anything yet' if @installed_gems.nil?
    @installed_gems.any? { |s| s.name == 'rspec' }
  end

  ##
  # Path to ruby

  def ruby
    ruby_exe = Config::CONFIG['ruby_install_name'] + Config::CONFIG['EXEEXT']
    File.join Config::CONFIG['bindir'], ruby_exe
  end

  ##
  # Sets up a sandbox, installs the gem, runs the tests and returns a Build
  # object.

  def run
    sandbox_cleanup # don't clean up at the end so we can review
    sandbox_setup

    build = Tinderbox::Build.new
    full_log = []
    run_log = nil

    full_log << "### installing #{@gem_name}-#{@gem_version} + dependencies"
    full_log << install

    full_log << "### testing #{@gemspec.full_name}"
    test
    full_log << @log

    build.duration = @duration
    build.successful = @successful
    build.log = full_log.join "\n"

    Gem::SourceInfoCache.cache.write_cache

    return build
  end

  ##
  # Runs shell command +command+ and records the command's output and the time
  # it took to run.  Returns true if evidence of a test run were found in the
  # command output.

  def run_command(command)
    start = Time.now
    @log << "### #{command}\n"
    begin
      Timeout.timeout @timeout, RunTimeout do
        @log << `#{command} 2>&1`
      end
    rescue RunTimeout
      @log << "!!! failed to complete in under #{@timeout} seconds\n"
      `ruby -e 'exit 1'` # force $?
    end
    @duration += Time.now - start

    passed? $CHILD_STATUS
  end

  ##
  # Cleans up the gem sandbox.

  def sandbox_cleanup
    FileUtils.remove_dir @sandbox_dir rescue nil

    raise "#{@sandbox_dir} not empty" if File.exist? @sandbox_dir
  end

  ##
  # Sets up a new gem sandbox.

  def sandbox_setup
    raise "#{@sandbox_dir} already exists" if
      File.exist? @sandbox_dir

    FileUtils.mkpath @sandbox_dir
    FileUtils.mkpath File.join(@sandbox_dir, 'gems')

    ENV['GEM_HOME'] = @sandbox_dir
    Gem.clear_paths
    Gem::SourceInfoCache.reset
  end

  ##
  # Tries a best-effort at running the tests or specifications for a gem.  The
  # following commands are tried, and #test stops on the first evidence of a
  # test run.
  #
  # 1. rake test
  # 2. rake spec
  # 3. make test
  # 4. ruby -Ilib -S testrb test
  # 5. spec spec/*

  def test
    Dir.chdir @gemspec.full_gem_path do
      if File.exist? 'Rakefile' then
        install_rake unless rake_installed?
        return if run_command "#{ruby} -S rake test"
      end

      if File.exist? 'Rakefile' and `rake -T` =~ /^rake spec/ then
        install_rspec '`rake spec`' unless rspec_installed?
        return if run_command "#{ruby} -S rake spec"
      end

      if File.exist? 'Makefile' then
        return if run_command 'make test'
      end

      if File.directory? 'test' then
        return if run_command "#{ruby} -I#{gem_lib_paths} -S #{testrb} test"
      end

      if File.directory? 'spec' then
        install_rspec 'spec DIRECTORY' unless rspec_installed?
        return if run_command "#{ruby} -S spec spec/*"
      end

      @log << "!!! could not figure out how to test #{@gemspec.full_name}"
      @successful = false
    end
  end

  ##
  # Path to testrb

  def testrb
    Config::CONFIG['ruby_install_name'] =~ /ruby/
    testrb_exe = "testrb#{$'}"
    testrb_exe += '.bat' if RUBY_PLATFORM =~ /mswin/
    File.join Config::CONFIG['bindir'], testrb_exe
  end

end

