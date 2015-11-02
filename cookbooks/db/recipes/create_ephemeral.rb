rightscale_marker

class Chef::Recipe
  include RightScale::BlockDeviceHelper
end

NICKNAME = get_device_or_default(node, :device2, :nickname)

  #A check if device already exists
  mount_point = '/mnt/ephemeral'
  platform = ::RightScale::Tools::Platform.factory
  device_exists = platform.get_device_for_mount_point(mount_point)
  log "#{device_exists} already exists at #{mount_point}" if device_exists
  return if device_exists

block_device NICKNAME do
    mount_point '/mnt/ephemeral'
    stripe_count node[:db][:ephemeral_stripe_count]
    vg_data_percentage node[:db][:ephemeral_vg_data_percentage]
    volume_size node[:db][:ephemeral_volume_size]
    iops node[:db][:ephemeral_iops] || ""
    action :create
end

