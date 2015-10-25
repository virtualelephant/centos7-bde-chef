#
# Cookbook Name:: mesos
# Recipe:: docker
#
# Copyright (C) 2013 Medidata Solutions, Inc.
# Portions Copyright (c) 2014 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

return unless node.role?('mesos_docker')

set_bootstrap_action(ACTION_INSTALL_PACKAGE, 'docker-engine', true)

# setup the proper repo for pulling Docker
template '/etc/yum.repos.d/docker.repo' do
  source 'docker.repo.erb'
  owner 'root'
  group 'root'
  mode '0644'
end

# install docker
package 'epel-release'
package 'docker-engine'

bash 'config docker containerizer for mesos' do
  not_if 'grep docker /etc/mesos-slave/containerizers'
  code <<-EOH
    echo "other_args='--insecure-registry 10.0.0.0/8'" >> /etc/sysconfig/docker
    echo 'docker,mesos' > /etc/mesos-slave/containerizers
    echo '5mins' > /etc/mesos-slave/executor_registration_timeout
  EOH
  #notifies :run, 'bash[restart-mesos-slave]', :delayed
end

service 'docker' do
  action [ :enable, :start ]
end

return if File.exist?("#{node['mesos']['python_site_dir']}/mesos.egg")
set_bootstrap_action('Installing mesos docker executer', '', true)

# install mesos docker executor
package 'python-setuptools'

directory '/var/lib/mesos/executors' do
  owner 'root'
  group 'root'
  mode 00755
  recursive true
  action :create
end

remote_file '/var/lib/mesos/executors/docker' do
  owner 'root'
  group 'root'
  source 'https://raw.github.com/mesosphere/mesos-docker/master/bin/mesos-docker'
  mode 00755
  not_if { ::File.exist?('/var/lib/mesos/executors/docker') }
end

remote_file "#{Chef::Config[:file_cache_path]}/mesos.egg" do
  owner 'root'
  group 'root'
  source node['mesos']['python_egg']
  mode 00755
  not_if { ::File.exist?("#{Chef::Config[:file_cache_path]}/mesos.egg") }
end

bash 'install-mesos-egg' do
  user 'root'
  group 'root'
  code <<-EOH
    easy_install "#{Chef::Config[:file_cache_path]}/mesos.egg"
  EOH
  not_if { ::File.exist?("#{node['mesos']['python_site_dir']}/mesos.egg") }
end
