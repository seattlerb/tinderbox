set :mri_1_8, 'ruby-1.8.6-p114.tar.gz'
set :mri_1_8_dir, 'ruby-1.8.6-p114'

role :mri_1_8 do

  remote_task :build_ruby do
    run [
      "cd #{tinderbox_dir}/#{mri_1_8_dir}",
      "./configure --prefix=#{tinderbox_dir}/MRI_1_8",
      "make",
    ].join(' && ')
  end

  remote_task :install_ruby do |task, args|
    run [
      "rm -rf #{tinderbox_dir}/MRI_1_8",
      "cd #{tinderbox_dir}/#{mri_1_8_dir}",
      "make install",
    ].join(' && ')

    ruby_bin[task.target_host] = "#{tinderbox_dir}/MRI_1_8/bin/ruby"

    run <<-EOF
echo $PATH | grep MRI_1_8
if [ $? -gt 0 ]; then
  echo PATH=\\$PATH:#{File.dirname ruby_bin[task.target_host]} >> ~/.bashrc
fi
    EOF
  end

  remote_task :unpack do
    run [
      "cd #{tinderbox_dir}",
      "rm -rf #{mri_1_8_dir}",
      "tar xzf #{mri_1_8}",
    ].join(' && ')
  end

  remote_task :upload => File.join(distfiles, mri_1_8) do
    rsync File.join(distfiles, mri_1_8), "#{TINDERBOX_DIR}/"
  end

end

