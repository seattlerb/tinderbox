require 'test/unit'
require 'rubygems'
require 'rc_rest/uri_stub'
require 'rc_rest/net_http_stub'
require 'test/zentest_assertions'

require 'tinderbox/build'

class TestTinderboxBuild < Test::Unit::TestCase

  def setup
    URI::HTTP.responses = []
    URI::HTTP.uris = []

    Net::HTTP.params = []
    Net::HTTP.paths = []
    Net::HTTP.responses = []

    @build = Tinderbox::Build.new
  end

  def test_duration
    @build.duration = 5
    assert_equal 5, @build.duration
  end

  def test_log
    @build.log = 'some crap'
    assert_equal 'some crap', @build.log
  end
  
  def test_successful
    @build.successful = true
    assert_equal true, @build.successful
  end

  def test_submit
    Net::HTTP.responses << <<-EOF
<ok>
  <build>
    <id>100</id>
    <created_on>#{Time.now}</created_on>
    <duration>1.5</duration>
    <guilty_party></guilty_party>
    <successful>true</successful>
    <target_id>100</target_id>
    <version_id>101</version_id>
  </build>
</ok>
    EOF

    @build.log = "*** blah\nfailed"
    @build.successful = false
    @build.duration = 1.5

    srand 0

    @build.submit 101, 100, 'firebrigade.example.com', 'username', 'password'

    assert_empty Net::HTTP.responses

    assert_equal 1, Net::HTTP.paths.length
    assert_equal '/api/REST/add_build', Net::HTTP.paths.shift

    assert_equal 1, Net::HTTP.params.length

    expected = <<-EOF.strip
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"duration\"\r
\r
1.5\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"hash\"\r
\r
e99435ecca5025c0e3a6f7e98fc91b7e\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"log\"\r
\r
*** blah
failed\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"successful\"\r
\r
false\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"target_id\"\r
\r
100\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"user\"\r
\r
username\r
--ac_2f_75_c0_43_fb_c3_67\r
Content-Disposition: form-data; name=\"version_id\"\r
\r
101\r
--ac_2f_75_c0_43_fb_c3_67--
    EOF
    assert_equal expected, Net::HTTP.params.shift
  end

end

