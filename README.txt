= Tinderbox

by Eric Hodel

http://seattlerb.rubyforge.org/tinderbox

== DESCRIPTION:

Tinderbox tests projects and tries to make them break by running them on as
many different platforms as possible.

== FEATURES/PROBLEMS:

* Tests gems in a sandbox
* Submits gem test results to http://firebrigade.seattlerb.org
* Understands test/unit and RSpec

== SYNOPSIS:

  tinderbox_gem_run -u 'my username' -p 'my password' -s tinderbox.example.com

== REQUIREMENTS:

* RubyGems 0.9.1
* firebrigade_api
* RSpec
* Rake
* Connection to the internet

== INSTALL:

* sudo gem install tinderbox

