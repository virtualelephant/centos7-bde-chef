#
# Cookbook Name:: zookeeper
# Recipe::        default
#

#
#   Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

include_recipe "java::sun"
include_recipe "hadoop_common::pre_run"
include_recipe "hadoop_common::mount_disks"
include_recipe "hadoop_cluster::update_attributes"

# alias home dir
if is_pivotalhd_distro
  node.normal[:zookeeper][:home_dir] = '/usr/lib/gphd/zookeeper'
end
force_link("/usr/lib/zookeeper", node[:zookeeper][:home_dir])

group "hadoop" do
  action [:create]
end

group "zookeeper" do
  action [:create]
end

user "zookeeper" do
  group   "zookeeper"
  shell   "/bin/bash"
  password   nil
  supports   :manage_home => false
  action     [:create, :manage]
end

# Install Zookeeper
set_bootstrap_action(ACTION_INSTALL_PACKAGE, 'zookeeper', true)

template '/etc/pki/rpm-gpg/RPM-GPG-KEY-mesosphere' do
  source 'RPM-GPG-KEY-mesosphere.erb'
  action :create_if_missing
end

if is_install_from_tarball
  include_recipe "zookeeper::install_from_tarball"
else
  include_recipe "zookeeper::install_from_package"
end

#link "/etc/zookeeper" do
#  to node[:zookeeper][:home_dir] + "/conf"
#end

# link Zookeeper data dir and log dir to the mounted data disk to get larger disk space
# assumes we have at least two data disks
data_dir = disks_mount_points[0]
log_dir = disks_mount_points.size > 1? disks_mount_points[1] : data_dir

if data_dir && log_dir
  dirs = { '/var/lib/zookeeper' => data_dir + '/zookeeper/data', '/var/log/zookeeper' => log_dir + '/zookeeper/log'}
  dirs.map do |src, des|
    target = "#{des}"
    directory target do
      owner "zookeeper"
      group "zookeeper"
      mode "0755"
      recursive true
    end

#    link src do
#      to target
#    end
  end
end

dirs = ["/var/run/zookeeper"]
dirs += ["/var/lib/zookeeper"] unless data_dir
dirs += ["/var/log/zookeeper"] unless log_dir
dirs.each do |dir|
  directory dir do
    owner "zookeeper"
    group "zookeeper"
    mode "0755"
  end
end

ips = zookeepers_ip
listen_on_ip = ip_of_hdfs_network(node)
index = 0
servers = ""
if ips.size > 1
  ips.each do |ip|
    servers += "server.#{index}=#{ip}:#{@node[:zookeeper][:peer_port]}:#{@node[:zookeeper][:leader_port]}\n"
    index += 1
  end
else
  servers = "server=#{ip}:#{@node[:zookeeper][:peer_port]}:#{@node[:zookeeper][:leader_port]}"
end

%w[ zoo.cfg log4j.properties ].each do |file|
  template "/etc/zookeeper/conf/#{file}" do
    owner "zookeeper"
    source "#{file}.erb"
    mode "0644"
    variables(:servers => servers, :listen_on_ip => listen_on_ip)
  end
end

#template "/etc/zookeeper/java.env" do
#  source "java.env.erb"
#  mode "0755"
#  owner "zookeeper"
#  group "zookeeper"
#end

template "/var/lib/zookeeper/myid" do
  source "myid.erb"
  owner "zookeeper"
  group "zookeeper"
  variables(:myid => node[:facet_index])
end

#template "#{node[:zookeeper][:home_dir]}/bin/zkEnv.sh" do
#  source "zkEnv.sh.erb"
#  owner "zookeeper"
#  group "zookeeper"
#  mode  "0755"
#end

# zookeeper-3.4.5 reads zkEnv.sh from dir libexec
#file = "#{node[:zookeeper][:home_dir]}/libexec/zkEnv.sh"
#template file do
#  only_if { File.exists?(file) }
#  source "zkEnv.sh.erb"
#  owner "zookeeper"
#  group "zookeeper"
#  mode  "0755"
#end

#template "/etc/init.d/zookeeper-server" do
#  source "zookeeper-server.erb"
#  owner "root"
#  group "root"
#  mode  "0755"
#end

## Launch Service
set_bootstrap_action(ACTION_START_SERVICE, node[:zookeeper][:zookeeper_service_name])

is_zookeeper_running = system("service #{node[:zookeeper][:zookeeper_service_name]} status")
service "restart-#{node[:zookeeper][:zookeeper_service_name]}" do
  service_name node[:zookeeper][:zookeeper_service_name]
  supports :status => true, :restart => true

  subscribes :restart, resources("template[/etc/zookeeper/zoo.cfg]"), :delayed
  subscribes :restart, resources("template[/etc/zookeeper/log4j.properties]"), :delayed
  subscribes :restart, resources("template[/etc/zookeeper/java.env]"), :delayed
  subscribes :restart, resources("template[#{node[:zookeeper][:home_dir]}/bin/zkEnv.sh]"), :delayed
  notifies :create, resources("ruby_block[#{node[:zookeeper][:zookeeper_service_name]}]"), :immediately
end if is_zookeeper_running

service "start-#{node[:zookeeper][:zookeeper_service_name]}" do
  service_name node[:zookeeper][:zookeeper_service_name]
  action [ :disable, :start ]
  supports :status => true, :restart => true

  notifies :create, resources("ruby_block[#{node[:zookeeper][:zookeeper_service_name]}]"), :immediately
end

# Register with cluster_service_discovery
provide_service(node[:zookeeper][:zookeeper_service_name])

clear_bootstrap_action
