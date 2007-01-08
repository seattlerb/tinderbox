require 'tinderbox'

require 'English'
require 'fileutils'
require 'open-uri'
require 'stringio'
require 'timeout'

require 'rubygems'
require 'rubygems/remote_installer'

##
# Tinderbox::GemRunner tests a gem and creates a Tinderbox::Build holding the
# results of the test run.

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
                                                 :cache_dir => @cache_dir
    @remote_installer.ui = Gem::SilentUI.new
    @gemspec = nil
    @installed_gems = nil

    @timeout = 120
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
  # Install the sources gem into the sandbox gem repository.

  def install_sources
    sources_gem = Dir[File.join(@host_gem_dir, 'cache', 'sources-*gem')].max

    installer = Gem::Installer.new sources_gem
    installer.install

    FileUtils.copy @host_gem_source_index, Gem::SourceInfoCache.new.cache_file
  end

  ##
  # Installs the rake gem into the sandbox

  def install_rake
    log = []
    log << "!!! HAS Rakefile, DOES NOT DEPEND ON RAKE!  NEEDS s.add_dependency 'rake'"

    retries = 5

    rake_version = Gem::SourceInfoCache.search(/^rake$/).last.version.to_s

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

    return log.join("\n") + "\n"
  end

  ##
  # Checks to see if the rake gem was installed by the gem under test

  def rake_installed?
    raise 'you haven\'t installed anything yet' if @installed_gems.nil?
    @installed_gems.any? { |s| s.name == 'rake' }
  end

  ##
  # Platform-specific shell redirection

  def redirector
    RUBY_PLATFORM =~ /mswin/ ? '1<&2' : '2>&1'
  end

  ##
  # Sets up a sandbox, installs the gem, runs the tests and returns a Build
  # object.

  def run
    sandbox_cleanup # don't clean up at the end so we can review
    sandbox_setup
    install_sources

    build = Tinderbox::Build.new
    full_log = []
    run_log = nil

    full_log << "### installing #{@gem_name}-#{@gem_version} + dependencies"
    full_log << install

    full_log << "### testing #{@gemspec.full_name}"
    duration, successful, run_log = test
    full_log << run_log

    build.duration = duration
    build.successful = successful
    build.log = full_log.join "\n"

    return build
  end

  ##
  # Runs shell command +command+ and returns the commands output and the time
  # it took to run.

  def run_command(command)
    start = Time.now
    output = "### #{command}\n"
    begin
      Timeout.timeout @timeout, RunTimeout do
        output << `#{command} #{redirector}`
      end
    rescue RunTimeout
      output << "!!! failed to complete in under #{@timeout} seconds\n"
      `ruby -e 'exit 1'` # force $?
    end
    duration = Time.now - start
    return output, duration
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
  end

  ##
  # Runs the tests for the gem.  Returns the time the tests took to run,
  # whether the tests where successful (exit code 0) and the log for the
  # tests.

  def test
    Dir.chdir @gemspec.full_gem_path do
      duration = nil
      log = nil

      if File.exist? 'Rakefile' then
        log = ''
        log << install_rake unless rake_installed?
        run_log, duration = run_command 'rake test'
        log << run_log
      elsif File.exist? 'Makefile' then
        log, duration = run_command 'make test'
      elsif File.directory? 'test' then
        log, duration = run_command 'ruby -Ilib -S testrb test'
      else
        log = "!!! could not figure out how to test #{@gemspec.full_name}"
        return [0, false, log]
      end

      successful = $CHILD_STATUS.exitstatus == 0
      if log =~ / (\d+) failures, (\d+) errors/ and
         $1 != '0' and $2 != '0' then
        log << "!!! Project has broken test target" if successful
        successful = false
      elsif log =~ / 0 assertions/ or log !~ / \d+ assertions/ then
        successful = false
        log << "!!! No test output indicating success found"
      end

      return [duration, successful, log]
    end
  end

end

