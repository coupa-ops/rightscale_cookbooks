rightscale_marker

class Chef::Recipe
  include RightScale::BlockDeviceHelper
end

block_device node[:db][:ephemeral_volume_nickname] do
    mount_point '/mnt/ephemeral'
    stripe_count node[:db][:ephemeral_stripe_count]
    vg_data_percentage node[:db][:ephemeral_vg_data_percentage]
    volume_size node[:db][:ephemeral_volume_size]
    iops node[:db][:ephemeral_iops] || ""
    action :create
end

