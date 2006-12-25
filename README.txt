= Tinderbox

by Eric Hodel

http://seattlerb.rubyforge.org/tinderbox

== DESCRIPTION:
  
Tinderbox tests projects and tries to make them break by running them on as
many different platforms as possible.

== FEATURES/PROBLEMS:
  
* Only knows how to test gems
* Doesn't ignore network problems when fetching gems

== SYNOPSYS:

  tinderbox_gem_run -u 'my username' -p 'my password' -s tinderbox.example.com

== REQUIREMENTS:

* rubygems-0.9.1
* firebrigade_api-1.0.0
* Persistent connection to the internet

== INSTALL:

* sudo gem install tinderbox

