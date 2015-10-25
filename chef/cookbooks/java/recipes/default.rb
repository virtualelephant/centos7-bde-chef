#
# Cookbook Name:: java
# Recipe:: default
#
# Copyright 2008-2010, Opscode, Inc.
# Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

case node.platform
when "debian","ubuntu"
  nil
else
  Chef::Log.info("Installation of Java packages are only supported on Debian/Ubuntu at this time. Please ensure it's already installed in the OS.")
  return
end

include_recipe "java::#{node["java"]["install_flavor"]}"

current_java_version_pattern = (node.java.install_flavor == 'sun') ? /Java HotSpot\(TM\)/ : /^OpenJDK/

# force ohai to run and pick up new languages.java data
ruby_block "reload_ohai" do
  block do
    o = Ohai::System.new
    o.all_plugins
    node.automatic_attrs.merge! o.data
  end
  action :nothing
end

execute "update-java-alternatives" do
  command "update-java-alternatives --jre -s java-6-#{node["java"]["install_flavor"]}"
  returns 0
  only_if do platform?("ubuntu", "debian") end
  action :nothing
  notifies :create, resources(:ruby_block => "reload_ohai"), :immediately
end

node.run_state[:java_pkgs].each do |pkg|
  package pkg do
    action :install
    if platform?("ubuntu", "debian")
      if node.java.install_flavor == "sun"
        response_file "java.seed"
      end
      notifies :run, resources(:execute => "update-java-alternatives"), :delayed
    end
  end
end

# re-run update-java-alternatives if our java flavor changes
if node.languages.attribute?("java")
  current_hotspot_name = node.languages.java.hotspot.name rescue "NONE"
  unless current_hotspot_name.match(current_java_version_pattern)
    log "Java install_flavor has changed, re-running 'update-java-alternatives'" do
      level :info
      notifies :run, resources(:execute => "update-java-alternatives"), :immediately
    end
  end
end

node.run_state.delete(:java_pkgs)
