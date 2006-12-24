require 'tinderbox'

require 'rubygems'
require 'firebrigade/api'

class Tinderbox::Build

  def submit(project_id, target_id, host, username, password)
    fa = Firebrigade::API.new host, username, password
    fa.add_build project_id, target_id, successful, duration, log
  end

end

