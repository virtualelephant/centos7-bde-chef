#
# Cookbook Name:: java
# Recipe:: sun
#
# Copyright 2010, Opscode, Inc.
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

node.run_state[:java_pkgs] = value_for_platform(
  ["debian","ubuntu"] => {
    "default" => ["sun-java6-jre"]
  },
  "default" => ["sun-java6-jre"]
)

case node.platform
when "debian","ubuntu"
  include_recipe "apt"

  template "/etc/apt/sources.list.d/canonical.com.list" do
    mode "0644"
    source "canonical.com.list.erb"
    notifies :run, resources(:execute => "apt-get update"), :immediately
    action :create
  end
else
  Chef::Log.info("Installation of Java packages are only supported on Debian/Ubuntu at this time. Please ensure it's already installed in the OS.")
end
