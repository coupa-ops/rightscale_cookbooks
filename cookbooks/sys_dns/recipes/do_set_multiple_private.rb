#
# Cookbook Name:: sys_dns
#
# Copyright RightScale, Inc. All rights reserved.
# All access and use subject to the RightScale Terms of Service available at
# http://www.rightscale.com/terms.php and, if applicable, other agreements
# such as a RightScale Master Subscription Agreement.

rightscale_marker

# This will set the DNS records identified by the node[:sys_dns][:ids] input to the first private IP address of the instance.

rec_ids=node[:sys_dns][:ids].split(',')
log "Setting DNS records identified by the array of ids: #{rec_ids}"
rec_ids.each do |rec_id|
  sys_dns "default" do
    id rec_id
    address node[:cloud][:private_ips][0]
    region node[:sys_dns][:region]
    action :set
  end
end
