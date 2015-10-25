#
# Cookbook Name:: hbase
# Recipe::        client
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
include_recipe "hadoop_cluster"
include_recipe "hbase"

%w[ hbase-rest hbase-thrift ].each do |file|
  template "/etc/init.d/#{file}" do
    owner "root"
    mode "0755"
    source "#{file}.erb"
  end
end

wait_for_hbase_master_service

service "start-#{node[:hbase][:rest_service_name]}" do
  service_name node[:hbase][:rest_service_name]
  supports :status => true, :restart => true
  action [:enable, :start]
end
provide_service(node[:hbase][:rest_service_name])

service "start-#{node[:hbase][:thrift_service_name]}" do
  service_name node[:hbase][:thrift_service_name]
  supports :status => true, :restart => true
  action [:enable, :start]
end
provide_service(node[:hbase][:thrift_service_name])
