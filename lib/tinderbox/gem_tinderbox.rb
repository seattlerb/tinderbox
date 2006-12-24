require 'tinderbox'
require 'tinderbox/gem_runner'
require 'tinderbox/build'
require 'rubygems/source_info_cache'

require 'optparse'
require 'rbconfig'
require 'socket'

require 'rubygems'
require 'firebrigade/cache'

class Tinderbox::GemTinderbox

  attr_accessor :root

  def self.process_args(args)
    opts_file = File.expand_path '~/.gem_tinderbox'
    options = {}

    if File.exist? opts_file then
      File.readlines(opts_file).map { |l| l.chomp.split '=', 2 }.each do |k,v|
        v = true  if v == 'true'
        v = false if v == 'false'
        options[k.intern] = v
      end
    end

    options[:Daemon] ||= false

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

  def self.run(args = ARGV)
    options = process_args args

    tinderbox = new options[:Server], options[:Username], options[:Password]
    tinderbox.root = options[:Root]

    if options[:Daemon] then
      require 'webrick/server'
      WEBrick::Daemon.start
    end

    tinderbox.run

  rescue Interrupt, SystemExit # ignore
  rescue Exception => e
    puts "#{e.message}(#{e.class}):"
    puts "\t#{e.backtrace.join "\n\t"}"
    exit 1
  end

  def initialize(host, username, password)
    @host = host
    @username = username
    @password = password
    @root = nil

    @source_info_cache = nil 
    @seen_gems = []
    @wait_time = 300

    @fc = Firebrigade::Cache.new @host, @username, @password
    @target_id = @fc.get_target_id
  end

  ##
  # Finds new gems in the source_info_cache

  def new_gems
    update_gems

    latest_gems = []
    source_info_cache.cache_data.each do |source, sic_e|
      latest_gems.push(*sic_e.source_index.latest_specs.values)
    end
    latest_gems.uniq! # HACK same gem from multiple sources, sorry!

    new_gems = latest_gems - @seen_gems

    @seen_gems = latest_gems

    new_gems
  end

  def run
    loop do
      new_gems.each do |spec|
        $stderr.puts "*** Checking #{spec.full_name}"
        version_id = @fc.get_version_id spec
        next if tested? version_id
        $stderr.puts "*** Ignighting #{spec.full_name} (http://#{@host}/version/show/#{version_id})"
        build = test_gem spec
        $stderr.puts "*** #{build.successful ? 'not flammable' : 'flammable!' }"
        build.submit version_id, @target_id, @host, @username, @password
      end

      sleep @wait_time
    end
  end

  ##
  # Rubygems' source info cache

  def source_info_cache
    return @source_info_cache if @source_info_cache
    @source_info_cache = Gem::SourceInfoCache.cache
  end

  ##
  # Tests the gem +spec+ and returns a Build containing its results.

  def test_gem(spec)
    runner = Tinderbox::GemRunner.new spec.name, spec.version.to_s, root
    runner.run
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

