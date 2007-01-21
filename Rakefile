# -*- ruby -*-

require 'rubygems'
require 'hoe'
require './lib/tinderbox.rb'

Hoe.new 'tinderbox', Tinderbox::VERSION do |p|
  p.rubyforge_name = 'seattlerb'
  p.summary = 'Tinderbox says, "I\'m gonna light you on fire."'
  p.description = p.paragraphs_of('README.txt', 2..5).join("\n\n")
  p.url = p.paragraphs_of('README.txt', 0)[2]
  p.changes = p.paragraphs_of('History.txt', 0..1).join("\n\n")
  p.author = 'Eric Hodel'
  p.email = 'drbrain@segment7.net'

  p.extra_deps << ['ZenTest', '>= 3.4.0']
  p.extra_deps << ['firebrigade_api', '>= 1.0.0']
  p.extra_deps << ['rspec', '>= 0.7.5.1']
end

# vim: syntax=Ruby
