##
# Tinderbox tests gems in a sandbox.  See Tinderbox::GemRunner and
# Tinderbox::GemTinderbox for further details.

module Tinderbox

  ##
  # This is the version of Tinderbox you are currently running.

  VERSION = '1.0.0'

  ##
  # Indicates an error while installing software we're going to test.

  class InstallError < RuntimeError; end

  ##
  # Indicates an error while building extensions for a gem we're going to
  # test.

  class BuildError < InstallError; end

  ##
  # Indicates an installation that cannot be performed automatically.

  class ManualInstallError < InstallError; end

  ##
  # A Struct that holds information about a Build.

  Build = Struct.new :successful, :duration, :log

end

