$TESTING = false unless defined? $TESTING
require 'tinderbox'
require 'tinderbox/gem_runner'
require 'tinderbox/build'
require 'rubygems/source_info_cache'

require 'optparse'
require 'rbconfig'
require 'socket'

require 'rubygems'
require 'firebrigade/cache'

##
# GemTinderbox is a tinderbox for RubyGems.

class Tinderbox::GemTinderbox

  ##
  # Root directory that the GemTinderbox will use.

  attr_accessor :root

  ##
  # Timeout for GemRunner.

  attr_accessor :timeout

  ##
  # Processes +args+ into options.

  def self.process_args(args)
    opts_file = File.expand_path '~/.gem_tinderbox'
    options = {}

    if File.exist? opts_file then
      File.readlines(opts_file).map { |l| l.chomp.split '=', 2 }.each do |k,v|
        v = true  if v == 'true'
        v = false if v == 'false'
        v = Integer(v) if k == 'Timeout'
        options[k.intern] = v
      end
    end

    options[:Daemon] ||= false
    options[:Timeout] ||= 120

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename $0} [options]"
      opts.separator ''
      opts.separator 'Options may also be set in the options file ~/.gem_tinderbox.'
      opts.separator ''
      opts.separator 'Example ~/.gem_tinderbox'
      opts.separator "\tServer=firebrigade.example.com"
      opts.separator "\tUsername=my username"
      opts.separator "\tPassword=my password"
      opts.separator "\tRoot=/path/to/tinderbox/root"

      opts.separator ''

      opts.on("-s", "--server HOST",
              "Firebrigade server host",
              "Default: #{options[:Server].inspect}",
              "Options file name: Server") do |server|
        options[:Server] = server
      end

      opts.on("-u", "--username USERNAME",
              "Firebrigade username",
              "Default: #{options[:Username].inspect}",
              "Options file name: Username") do |username|
        options[:Username] = username
      end

      opts.on("-p", "--password PASSWORD",
              "Firebrigade password",
              "Default: Read from ~/.gem_tinderbox",
              "Options file name: Password") do |password|
        options[:Password] = password
      end

      opts.separator ''

      opts.on("-t", "--timeout TIMEOUT",
              "Maximum time to wait for a gem's tests to",
              "finish",
              "Default: #{options[:Timeout]}",
              Numeric) do |timeout|
        options[:Timeout] = timeout
      end

      opts.on("-r", "--root ROOT",
              "Root directory for gem tinderbox",
              "Default: #{options[:Root]}",
              "Gems will be lit on fire here.") do |root|
        options[:Root] = root
      end

      opts.on("-d", "--daemonize",
              "Run as a daemon process",
              "Default: #{options[:Daemon]}") do |daemon|
        options[:Daemon] = true
      end
    end

    opts.version = Tinderbox::VERSION
    opts.release = nil

    opts.parse! args

    if options[:Server].nil? or
       options[:Username].nil? or
       options[:Password].nil? then
      $stderr.puts opts
      $stderr.puts
      $stderr.puts "Firebrigade Server not set"     if options[:Server].nil?
      $stderr.puts "Firebrigade Username not set" if options[:Username].nil?
      $stderr.puts "Firebrigade Password not set" if options[:Password].nil?
      exit 1
    end

    return options
  rescue OptionParser::ParseError
    $stderr.puts opts
    exit 1
  end

  ##
  # Starts a GemTinderbox.

  def self.run(args = ARGV)
    options = process_args args

    tinderbox = new options[:Server], options[:Username], options[:Password]
    tinderbox.root = options[:Root]
    tinderbox.timeout = options[:Timeout]

    if options[:Daemon] then
      require 'webrick/server'
      WEBrick::Daemon.start
    end

    tinderbox.run

  rescue Interrupt, SystemExit
    exit
  rescue Exception => e
    puts "#{e.message}(#{e.class}):"
    puts "\t#{e.backtrace.join "\n\t"}"
    exit 1
  end

  ##
  # Creates a new GemTinderbox that will submit results to +host+ as
  # +username+ using +password+.

  def initialize(host, username, password)
    @host = host
    @username = username
    @password = password
    @root = nil
    @timeout = 120

    @source_info_cache = nil 
    @seen_gem_names = []
    @wait_time = 300

    @fc = Firebrigade::Cache.new @host, @username, @password
    @target_id = nil
  end

  ##
  # Finds new gems in the source_info_cache

  def new_gems
    update_gems

    latest_gems = {}
    source_info_cache.cache_data.each do |source, sic_e|
      sic_e.source_index.latest_specs.each do |name, spec|
        latest_gems[name] = spec
      end
    end

    new_gem_names = latest_gems.keys - @seen_gem_names

    @seen_gem_names = latest_gems.keys

    latest_gems.values_at(*new_gem_names)
  end

  ##
  # Tests all the gems, then waits a while and tests anything that is new in
  # the index.  If an unhandled error is encountered, GemTinderbox waits a
  # minute then starts from the beginning.  (Since information is cached,
  # GemTinderbox won't pound on Firebrigade.)

  def run
    test_sanity

    @seen_gem_names = []
    @target_id ||= @fc.get_target_id

    loop do
      new_gems.each do |spec| run_spec spec end
      sleep @wait_time
    end
  rescue RCRest::CommunicationError, Gem::RemoteFetcher::FetchError,
         Gem::RemoteSourceException => e
    wait = Time.now + 60

    $stderr.puts e.message
    $stderr.puts "Will retry at #{wait}"

    unless $TESTING then
      sleep 60
      retry
    end
  end

  ##
  # Runs Gem::Specification +spec+ using a GemRunner then submits the results
  # to Firebrigade.

  def run_spec(spec)
    $stderr.puts "*** Checking #{spec.full_name}"

    version_id = @fc.get_version_id spec
    return if tested? version_id

    $stderr.puts "*** Igniting (http://#{@host}/gem/show/#{spec.name}/#{spec.version})"
    begin
      build = test_gem spec
    rescue Tinderbox::BuildError, Tinderbox::InstallError => e
      @seen_gem_names.delete spec.full_name
      $stderr.puts "*** Failed to install (#{e.class})"
      return
    rescue Tinderbox::InstallError => e
      $stderr.puts "*** Failed to install (#{e.class}), will try again later"
      return
    end

    if build.successful then
      $stderr.puts "*** I couldn't light #{spec.full_name} on fire"
    else
      $stderr.puts "*** I lit #{spec.full_name} on fire!"
    end

    build.submit version_id, @target_id, @host, @username, @password

    build
  end

  ##
  # Rubygems' source info cache

  def source_info_cache
    return @source_info_cache if @source_info_cache
    @source_info_cache = Gem::SourceInfoCache.cache
  end

  ##
  # Tests the Gem::Specification +spec+ and returns a Build containing its
  # results.

  def test_gem(spec)
    runner = Tinderbox::GemRunner.new spec.name, spec.version.to_s, root
    runner.timeout = @timeout
    runner.run
  end

  ##
  # Makes sure Tinderbox is sane and in a sane environment

  def test_sanity
    tgr = Tinderbox::GemRunner.new 'tinderbox', Tinderbox::VERSION, root
  end

  ##
  # Checks the server to see if +version_id+ has been tested.

  def tested?(version_id)
    !!@fc.get_build_id(version_id, @target_id)
  end

  ##
  # Refreshes Rubygems' source info cache

  def update_gems
    source_info_cache.refresh
  end

end

