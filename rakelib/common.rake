require 'tempfile'

task :allow_ssh do
  ssh = Socket.getservbyname 'ssh'

  begin
    groups = ec2.describe_security_groups security_group
  rescue RightAws::AwsError => e
    raise unless e.message =~ /^InvalidGroup\.NotFound/

    ec2.create_security_group security_group, security_group

    ec2.authorize_security_group_IP_ingress security_group, ssh, ssh
  end
end

remote_task :clean_ec2 do
  run "rm -r #{TINDERBOX_DIR}"
end

task :console, :tinderbox do |task, args|
  instance = args[:tinderbox]

  console = ec2.get_console_output instance

  puts console[:timestamp]
  puts '-' * 78
  puts console[:aws_output]
end

task :create_key do
  keys = ec2.describe_key_pairs

  unless keys.map { |k| k[:aws_key_name] }.include? ssh_key_name then
    new_key = ec2.create_key_pair ssh_key_name

    key_file = File.join ec2_dir, "#{new_key[:aws_key_name]}.key"

    open key_file, 'w', 0600 do |io|
      io.write new_key[:aws_material]
    end

    puts "Added key #{new_key[:aws_fingerprint]}" if $TRACE
  end
end

task :delete_key, :key_name do |task, args|
  raise "no key name given" if args[:key_name].nil? or args[:key_name].empty?

  ec2.delete_key_pair args[:key_name]

  FileUtils.rm_f File.join(ec2_dir, "#{args[:key_name]}.key")
end

task :ec2 do
  set :ec2_dir, File.expand_path(File.join('~', '.ec2'))
  FileUtils.mkdir_p ec2_dir unless File.directory? ec2_dir

  set :instances_dir, File.join(ec2_dir, 'instances')
  FileUtils.mkdir instances_dir unless File.directory? instances_dir

  access_key = File.read(File.join(ec2_dir, 'access_key')).chomp
  secret_key = File.read(File.join(ec2_dir, 'secret_access_key')).chomp

  if access_key.empty? or secret_key.empty? then
    raise "access_key or secret_access_key not found in #{ec2_dir}"
  end

  logger = Logger.new $stderr
  logger.level = Logger::UNKNOWN

  set :ec2, RightAws::Ec2.new(access_key, secret_key, :logger => logger)
end

task :images, :owner do |task, args|
  owner = args[:owner]

  images = ec2.describe_images_by_owner owner

  images = images.sort_by { |image| image[:aws_id] }
  images.each do |image|
    next unless image[:aws_product_codes].nil? or
                image[:aws_product_codes].empty?
    next unless image[:aws_image_type] == 'machine'
    puts "#{image[:aws_id]} (#{image[:aws_architecture]}) #{image[:aws_location]}"
  end
end

remote_task :install_rubygems do |task, args|
  run [
    "cd #{tinderbox_dir}",
    "tar xzf #{rubygems}",
    "cd #{rubygems_dir}",
    "#{ruby_bin[task.target_host]} setup.rb --no-rdoc --no-ri"
  ].join(' && ')

  gem_bin[task.target_host] = "#{tinderbox_dir}/MRI_1_8/bin/gem"
end

remote_task :install_tinderbox do |task, args|
  run [
    "cd #{tinderbox_dir}",
    "#{gem_bin[task.target_host]} install #{hoe_gem} --no-rdoc --no-ri",
    "#{gem_bin[task.target_host]} install #{tinderbox_gem} --no-rdoc --no-ri",
  ].join(' && ')
end

task :keys do
  ec2.describe_key_pairs.each do |key|
    puts "#{key[:aws_key_name]} #{key[:aws_fingerprint]}"
  end
end

remote_task :run_tinderbox do |task, args|
  run "#{ruby_bin[task.target_host]} -S tinderbox_gem_run"
end

remote_task :setup do
  run "mkdir -p #{TINDERBOX_DIR}"
  set :tinderbox_dir, run("cd #{TINDERBOX_DIR} && pwd").strip

  run 'yum install -y zlib-devel'
end

remote_task :setup_tinderbox do |task, args|
  Tempfile.open 'tinderbox' do |io|
    io.chmod 0600
    io.puts "Server=#{tinderbox_server}"
    io.puts "Username=#{tinderbox_username}"
    io.puts "Password=#{tinderbox_password}"
    io.puts "Once=true"

    io.flush

    rsync io.path, '~/.gem_tinderbox'
  end
end

task :shutdown do
  known = Dir[File.join(instances_dir, '*')].map { |path| File.basename path }

  instances = ec2.describe_instances.select do |instance|
    known.include?(instance[:aws_instance_id]) and
      (instance[:aws_state] != 'terminated' or
       instance[:aws_state] != 'shutting-down')
  end

  instance_ids = instances.map { |i| i[:aws_instance_id] }

  if $TRACE then
    instance_ids.each do |instance_id|
      puts "shutting down #{instance_id}"
    end
  end

  ec2.terminate_instances instance_ids

  FileUtils.rm_rf instances_dir
end

task :start_instances do
  known = Dir[File.join(instances_dir, '*')].map { |path| File.basename path }

  if known.empty? then
    threads = tinderboxen.map do |image_id, role|
      Thread.start do
        instances = ec2.run_instances image_id, 1, 1, [security_group],
          ssh_key_name

        instances.each do |instance|
          instance_id = instance[:aws_instance_id]

          open File.join(instances_dir, instance_id), 'w' do |io|
            io.puts role
          end

          loop do
            sleep 10

            instance = ec2.describe_instances(instance_id).first

            break if instance[:aws_state] == 'running'
          end

          hostname = instance[:dns_name]

          tries = 10

          loop do
            begin
              sh "ssh #{hostname} uptime"
              break
            rescue RuntimeError => e
              raise unless e.message =~ /Command failed/
              puts "failed" if $TRACE
            end

            tries -= 1
            break if tries <= 0

            sleep 30
          end

          puts "#{role} running on #{hostname}" if $TRACE

          role role, hostname
        end
      end
    end

    threads.each do |t| t.join end
  else
    instances = ec2.describe_instances known

    instances.each do |instance|
      next unless instance[:aws_state] == 'running'

      role_file = File.join instances_dir, instance[:aws_instance_id]
      role_name = File.read(role_file).chomp.intern
      role role_name, instance[:dns_name]
    end
  end
end

task :status do
  ec2.describe_instances.each do |instance|
    begin
      role = File.read File.join(instances_dir, instance[:aws_instance_id])
      role = role.chomp
    rescue Errno::ENOENT
      role = 'unknown'
    end

    if instance[:aws_state_code].to_i > 0 then
      start_time = Time.parse instance[:aws_launch_time]
      run_time = ((Time.now - start_time).to_i / 3600) + 1
      cost = " $%0.2f" % (run_time * 0.1)
    end

    puts "#{instance[:aws_instance_id]} #{role} #{instance[:aws_state]}#{cost} #{instance[:dns_name]}"
  end
end

remote_task :upload do
  rsync File.join(distfiles, rubygems),      "#{TINDERBOX_DIR}/"
  rsync File.join(distfiles, tinderbox_gem), "#{TINDERBOX_DIR}/"
  rsync File.join(distfiles, hoe_gem),       "#{TINDERBOX_DIR}/"
end

