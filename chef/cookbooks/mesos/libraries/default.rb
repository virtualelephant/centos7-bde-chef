module Mesosphere

  def mesos_masters_ip
    servers = all_providers_fqdn_for_role("mesos_master")
    Chef::Log.info("Mesos master nodes in cluster #{node[:cluster_name]} are: #{servers.inspect}")
    servers
  end

  def mesos_slaves_ip
    servers = all_providers_fqdn_for_role("mesos_slave")
    Chef::Log.info("Mesos slave nodes in cluster #{node[:cluster_name]} are: #{servers.inspect}")
    servers
  end
end

class Chef::Recipe; include Mesosphere; end
