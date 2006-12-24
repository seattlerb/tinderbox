module Tinderbox

  ##
  # This is the version of Tinderbox you are currently running.

  VERSION = '1.0.0'

  ##
  # Indicates an error while installing software we're going to test.

  class InstallError < RuntimeError; end

  ##
  # A struct to hold information about a Build.

  Build = Struct.new :successful, :duration, :log

end

