module Tinderbox

  ##
  # This is the version of Tinderbox you are currently running.

  VERSION = '1.0.0'

  ##
  # Indicates an error while installing software we're going to test.

  class InstallError < RuntimeError; end

  ##
  # Indicates an error while installing extensions to a gem we're going to
  # test.

  class BuildError < RuntimeError; end

  ##
  # Indicates an installation that cannot be performed automatically.

  class ManualInstallError < InstallError; end

  ##
  # A struct to hold information about a Build.

  Build = Struct.new :successful, :duration, :log

end

