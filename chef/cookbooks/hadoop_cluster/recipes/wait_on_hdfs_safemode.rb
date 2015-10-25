#
# Cookbook Name:: hadoop_cluster
# Recipe::        make_standard_hdfs_dirs
#
# Copyright 2010, Infochimps, Inc.
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

#
# This recipe checks if the HDFS is out of safenode: enough datanodes have come
# online as to allow HDFS filesystem operations
#
# This will spin indefinitely, so be careful where you put it in your
# run_list order.
#

execute "wait_for_hdfs_safemode" do
  command %Q{
    i=0
    while [ $i -le #{node[:hadoop][:namenode_wait_for_safemode_timeout]} ]
    do
      sleep 5
      if `hadoop dfsadmin -safemode get | grep -q OFF` ; then
        echo "namenode safemode is off"
        exit
      fi
      (( i+=5 ))
      echo "Wait until namenode leaves safemode. Already wait for $i seconds."
    done
    echo "Namenode stucks in safemode. Will explictlly tell it leave safemode."
    hadoop dfsadmin -safemode leave
  }
end

