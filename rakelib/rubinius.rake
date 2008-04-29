#RUBINIUS = 'rubinius.tar.gz'
#RUBINIUS_DIR = 'rubinius'
#
#role :rubinius do
#
#  remote_task :build do
#    run [
#      "cd #{tinderbox_dir}/#{RUBINIUS_DIR}",
#      "rake",
#    ].join(' && ')
#  end
#
#  remote_task :install_ruby do
#    run [
#      "rm -r #{tinderbox_dir}/rbx",
#      "cd #{tinderbox_dir}/#{RUBINIUS_DIR}",
#      "rake install",
#    ].join(' && ')
#
#    RUBY_BIN[:rubinius] = "#{tinderbox_dir}/rbx/bin/rbx"
#
#    run [
#      "echo \$PATH | grep rbx",
#      "if [ \$? -gt 0 ]; then",
#      "  echo PATH=\\\$PATH:#{RUBY_BIN[:rubinius]} >> ~/.bash_profile",
#      "fi",
#    ].join("\n")
#  end
#
#  remote_task :unpack do
#    run [
#      "cd #{tinderbox_dir}",
#      "rm -rf #{RUBINIUS_DIR}",
#      "tar xzf #{RUBINUS}",
#    ].join(' && ')
#  end
#
#  remote_task :upload do
#    rsync File.join(DISTFILES, RUBINIUS), "#{TINDERBOX_DIR}/"
#  end
#
#end
#
