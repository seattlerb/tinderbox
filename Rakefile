# -*- ruby -*-

require 'rubygems'
require 'hoe'
require 'vlad'
require 'right_aws'
$:.unshift 'lib'
require 'tinderbox'
require 'tinderbox/gem_runner'

Hoe.new 'tinderbox', Tinderbox::VERSION do |p|
  p.developer 'Eric Hodel', 'drbrain@segment7.net'
  p.summary = 'Tinderbox says, "I\'m gonna light you on fire."'
  p.description = p.paragraphs_of('README.txt', 2..5).join("\n\n")
  p.url = p.paragraphs_of('README.txt', 0)[2]
  p.changes = p.paragraphs_of('History.txt', 0..1).join("\n\n")

  p.extra_deps << ['ZenTest', '>= 3.4.0']
  p.extra_deps << ['firebrigade_api', '>= 1.0.0']
  p.extra_deps << ['rspec', '>= 0.7.5.1']
  p.extra_deps << ['rake', '>= 0.8']

#  p.spec_extras[:required_rubygems_version] =
#    Tinderbox::GemRunner::REQUIRED_RUBYGEMS_VERSION
end

TINDERBOX_DIR = '~/tinderbox'

set :ruby_bin, {}
set :gem_bin, {}

set :security_group, 'tinderbox'
set :ssh_key_name, 'tinderbox'

set :rubygems, 'rubygems-1.1.1.tgz'
set :rubygems_dir, 'rubygems-1.1.1'

set :hoe_gem, 'hoe-1.5.2.gem'
set :tinderbox_gem, 'tinderbox-2.0.0.gem'

set :distfiles, File.join(File.expand_path(File.dirname(__FILE__)), 'distfiles')

set :tinderbox_server, 'fb-test.seattlerb.org'
set :tinderbox_username, 'drbrain'
set :tinderbox_password, 'dummy firebrigade password'

set :tinderboxen, [
#  ['ami-f51aff9c', :jruby],    # x86
  ['ami-f51aff9c', :mri_1_8],  # x86
#  ['ami-f21aff9b', :mri_1_8],  # x86_64
#  ['ami-f51aff9c', :rubinius], # x86
#  ['ami-f21aff9c', :rubinius], # x86_64
]

desc "Show status of EC2 instances"
task :default => :status

desc "Allow SSH connections into tinderboxen"
task :allow_ssh => :ec2

desc "Build a Ruby implementation on a tinderbox instance"
remote_task :build_ruby => :unpack

desc "Removes tinderbox dir from tinderboxen"
remote_task :clean_ec2

desc "Display console output"
task :console => :ec2

desc "Create an SSH key for connecting to tinderboxen"
task :create_key => :ec2

desc "Delete an SSH key from ec2"
task :delete_key => :ec2

desc "List EC2 machine images available for use"
task :images => :ec2

desc "Install a Ruby implementation on a tinderbox instance"
remote_task :install_ruby => :build_ruby

desc "Install RubyGems on a tinderbox instance"
remote_task :install_rubygems => :install_ruby

desc "Install the tinderbox gem on a tinderbox instance"
remote_task :install_tinderbox => :install_rubygems

desc "List keys created on ec2"
task :keys => :ec2

desc "Run tinderbox"
remote_task :run_tinderbox => :setup_tinderbox

desc "Setup for running a tinderbox"
remote_task :setup => :startup

desc "Setup tinderbox for reporting"
remote_task :setup_tinderbox => :install_tinderbox

desc "Shut down all EC2 instances"
task :shutdown => :ec2

desc "Start EC2 instances"
task :start_instances => [:ec2, :create_key, :allow_ssh]

desc "Startup task"
task :startup => :start_instances

desc "Show status of EC2 instances"
task :status => :ec2

desc "Unpack a Ruby implementation on a tinderbox instance"
remote_task :unpack => :upload

desc "Upload necessary files for a tinderbox instance"
remote_task :upload => :setup

# vim: syntax=Ruby
