require 'tinderbox'

require 'rubygems'
require 'firebrigade/api'

##
# A set of Build results.

class Tinderbox::Build

  ##
  # Submit a Build to +host+ as +username+ using +password+ using
  # Firebrigade::API.  The Build will be added to project +project_id+ and
  # target +target_id+.

  def submit(project_id, target_id, host, username, password)
    fa = Firebrigade::API.new host, username, password
    fa.add_build project_id, target_id, successful, duration, log
  end

end

