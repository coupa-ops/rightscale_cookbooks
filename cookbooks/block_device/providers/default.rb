#
# Cookbook Name:: block_device
#
# Copyright RightScale, Inc. All rights reserved.
# All access and use subject to the RightScale Terms of Service available at
# http://www.rightscale.com/terms.php and, if applicable, other agreements
# such as a RightScale Master Subscription Agreement.

# @resource block_device

include RightScale::BlockDeviceHelper

action :restore_or_create_new do
  device = init(new_resource)
  lineage = new_resource.lineage
  from_master = new_resource.is_master
  timestamp = new_resource.timestamp_override == "" ?
      nil : new_resource.timestamp_override
  options = {}
  @api = RightScale::Tools::API.factory('1.5', options)
  timestamp = timestamp ? Time.at(timestamp.to_i + 1) : Time.now
  filter = [ "latest_before==#{timestamp.utc.strftime('%Y/%m/%d %H:%M:%S %z')}", "committed==true", "completed==true" ]
  filter << "from_master==true" if from_master
  backup = @api.client.backups.index(:lineage => lineage, :filter => filter )

  if backup.empty?
    Chef::Log.info "Did not find any snapshots in lineage: '#{lineage}' from_master: '#{from_master}' timestamp: '#{timestamp}'. Creating new volume"
    run_context.include_recipe "block_device::setup_block_device"
    run_context.include_recipe "block_device::do_primary_backup"
    run_context.include_recipe "block_device::do_primary_backup_schedule_enable"
  else
    Chef::Log.info "Found matching snapshot in lineage: '#{lineage}' from_master: '#{from_master}' timestamp: '#{timestamp}'. Doing primary restore"
    backup.first.show
    run_context.include_recipe "block_device::do_primary_restore"
    run_context.include_recipe "block_device::do_primary_backup"
    run_context.include_recipe "block_device::do_primary_backup_schedule_enable"
  end

end

# Sets up new block device
action :create do
  # Initialize new device by setting up resource attributes.
  # See cookbooks/block_device/libraries/block_device.rb for definition of
  # init method.
  device = init(new_resource)
  create_options = {
    :volume_size => new_resource.volume_size,
    :stripe_count => new_resource.stripe_count,
    :vg_data_percentage => new_resource.vg_data_percentage,
    :force => new_resource.force
  }
  if new_resource.iops && !new_resource.iops.empty?
    create_options[:iops] = new_resource.iops
  end
  create_options[:volume_type] = new_resource.volume_type
  # See rightscale_tools gem for implementation of "create" method.
  device.create(create_options)
end

# Creates a snapshot of given device
action :snapshot do
  backup_type = new_resource.backup_type

  # See cookbooks/block_device/libraries/block_device.rb for definition of
  # init method.
  device = init(new_resource, backup_type)
  backup_options = {
    :description => "RightScale data backup",
    :from_master => new_resource.is_master
  }

  # Check if all secondary backup inputs are set up. See
  # cookbooks/block_device/libraries/block_device.rb for definition of
  # init and secondary_checks methods.
  secondary_checks(new_resource) if backup_type == :secondary

  # See rightscale_tools gem for implementation of "create" method.
  device.snapshot(backup_type, new_resource.lineage, backup_options)
end

# Performs primary backup
action :primary_backup do
  # See cookbooks/block_device/libraries/block_device.rb for definition of
  # init method.
  device = init(new_resource)
  backup_options = {
    :description => "RightScale data backup",
    :from_master => new_resource.is_master,

    :max_snapshots => new_resource.max_snapshots,
    :keep_dailies => new_resource.keep_daily,
    :keep_weeklies => new_resource.keep_weekly,
    :keep_monthlies => new_resource.keep_monthly,
    :keep_yearlies => new_resource.keep_yearly,

    # ROS Based backups only
    :storage_key => new_resource.primary_user,
    :storage_secret => new_resource.primary_secret
  }
  # See rightscale_tools gem for definition of primary_backup method.
  device.primary_backup(new_resource.lineage, backup_options)
end

# Performs primary restore
action :primary_restore do
  # See cookbooks/block_device/libraries/block_device.rb for definition of
  # init method.
  device = init(new_resource)
  restore_args = {
    :timestamp => new_resource.timestamp_override == "" ?
      nil : new_resource.timestamp_override,
    :force => new_resource.force,
    :from_master => new_resource.is_master,
    :new_size_gb => new_resource.volume_size,
    :vg_data_percentage => new_resource.vg_data_percentage,
    :stripe_count => new_resource.stripe_count,
    :volume_size => new_resource.volume_size,

    # ROS Based backups only
    :storage_key => new_resource.primary_user,
    :storage_secret => new_resource.primary_secret
  }
  if new_resource.iops && !new_resource.iops.empty?
    restore_args[:iops] = new_resource.iops
  end
  restore_args[:volume_type] = new_resource.volume_type

  # See rightscale_tools gem for definition of primary_restore method.
  device.primary_restore(new_resource.lineage, restore_args)
end

# Performs secondary backup
action :secondary_backup do
  # Check if all secondary backup inputs are set up. See
  # cookbooks/block_device/libraries/block_device.rb for definition of
  # init and secondary_checks methods.
  secondary_checks(new_resource)
  device = init(new_resource, :secondary)
  # See rightscale_tools gem for the implementation of secondary_backup method.
  device.secondary_backup(new_resource.lineage)
end

# Performs for secondary restore
action :secondary_restore do
  # See cookbooks/block_device/libraries/block_device.rb for secondary_checks
  # and init methods.
  secondary_checks(new_resource)
  device = init(new_resource, :secondary)
  restore_args = {
    :timestamp => new_resource.timestamp_override == "" ?
      nil : new_resource.timestamp_override,
    :force => new_resource.force,
    :volume_size => new_resource.volume_size,
    :new_size_gb => new_resource.volume_size,
    :stripe_count => new_resource.stripe_count,
    :vg_data_percentage => new_resource.vg_data_percentage
  }
  if new_resource.iops && !new_resource.iops.empty?
    restore_args[:iops] = new_resource.iops
  end
  restore_args[:volume_type] = new_resource.volume_type

  # See rightscale_tools gem for implementation of secondary_restore method.
  device.secondary_restore(new_resource.lineage, restore_args)
end

# Unmounts and deletes the attached block device(s)
action :reset do
  # See cookbooks/block_device/libraries/block_device.rb for init method.
  device = init(new_resource)
  # See rightscale_tools gem for implementation of reset method.
  device.reset()
end

# Enables cron backups
action :backup_schedule_enable do

  # Verify parameters
  minute = new_resource.cron_backup_minute
  raise "ERROR: missing cron_backup_minute value." unless minute
  hour = new_resource.cron_backup_hour
  raise "ERROR: missing cron_backup_hour value." unless hour

  # Verify backup params used in cron recipe
  lineage = new_resource.lineage
  raise "ERROR: 'Backup Lineage' required for scheduled process" if lineage.empty?

  # Select recipe to schedule
  recipe = new_resource.cron_backup_recipe

  puts "Scheduling #{recipe} to run via cron job: Minute:#{minute} Hour:#{hour}"

  # Attributes for schedule will default to '*' if not provided so only
  # specify the schedule attributes if input is not an empty string.
  cron "RightScale remote_recipe #{recipe}" do
    minute "#{minute}" unless minute.empty?
    hour "#{hour}" unless hour.empty?
    user "root"
    command "rs_run_recipe --policy '#{recipe}' --name '#{recipe}' 2>&1 >> /var/log/rightscale_tools_cron_backup.log"
    action :create
  end

end

# Disables cron backups
action :backup_schedule_disable do
  # Select recipe to disable
  recipe = new_resource.cron_backup_recipe
  log "Disable #{recipe} cron job"

  cron "RightScale remote_recipe #{recipe}" do
    user "root"
    action :delete
  end
end
