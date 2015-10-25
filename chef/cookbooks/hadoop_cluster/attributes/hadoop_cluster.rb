#
#   Portions Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

default[:hadoop][:install_from_tarball] = true # install hadoop components using tarball or rpm
default[:hadoop][:is_hadoop_yarn] = false # is deploying a Hadoop version with YARN (e.g hadoop 0.23) ?
default[:hadoop][:hadoop_handle] = 'hadoop' # the prefix of the name of hadoop directory and package files
default[:hadoop][:distro_name] = 'apache' # which hadoop distro to deploy
default[:hadoop][:package_version]   = 'current' # hadoop package version

default[:hadoop][:hadoop_home_dir] = '/usr/lib/hadoop' # directory that HADOOP is installed in
default[:hadoop][:hadoop_conf_dir] = '/etc/hadoop/conf'

default[:hadoop][:service_stop_time] = 5 # waiting time for the hadoop service process to stop completely.

default[:hadoop][:namenode_wait_for_safemode_timeout] = 180 # 3 minutes

# HDFS and MapReduce settings
default[:hadoop][:dfs_replication             ] =  3
default[:hadoop][:reduce_parallel_copies      ] = 20
default[:hadoop][:tasktracker_http_threads    ] = 40
default[:hadoop][:jobtracker_handler_count    ] = 10
default[:hadoop][:namenode_handler_count      ] = 10
default[:hadoop][:datanode_handler_count      ] = 3

default[:hadoop][:compress_map_output         ] = 'false'
default[:hadoop][:output_compression_type     ] = 'BLOCK'

default[:hadoop][:mapred_userlog_retain_hours ] = 24
default[:hadoop][:mapred_jobtracker_completeuserjobs_maximum ] = 100

# Other recipes can add to this under their own special key, for instance
#  node[:hadoop][:extra_classpaths][:hbase] = '/usr/lib/hbase/hbase.jar:/usr/lib/hbase/lib/zookeeper.jar:/usr/lib/hbase/conf'
#
default[:hadoop][:extra_classpaths]  = { }

# uses /etc/default/hadoop-0.20 to set the hadoop daemon's heapsize
default[:hadoop][:hadoop_daemon_heapsize]            = 1000

# User groups
default[:groups]['hadoop'    ][:gid] = 300
default[:groups]['supergroup'][:gid] = 301
default[:groups]['hdfs'      ][:gid] = 302
default[:groups]['mapred'    ][:gid] = 303
default[:groups]['yarn'      ][:gid] = 304
# Users
default[:users]['hdfs'   ][:uid] = 302
default[:users]['mapred' ][:uid] = 303
default[:users]['yarn'   ][:uid] = 304
default[:users]['webuser'][:uid] = 305

# Allow hadoop to use system disk?
default[:hadoop][:use_root_as_scratch_vol]    = false
default[:hadoop][:use_root_as_persistent_vol] = false

default[:hadoop][:use_data_disk_as_log_vol] = true

# Extra directories for the Namenode metadata to persist to, for example an
# off-cluster NFS path (only necessary to use if you have a physical cluster)
set[:hadoop][:extra_nn_metadata_path] = nil

# Other hadoop settings
default[:hadoop][:max_balancer_bandwidth]     = 10485760  # bytes per second -- 10MB/s by default

#
# Tune cluster settings for size of instance
#
# These settings are mostly taken from the cloudera hadoop-ec2 scripts,
# informed by the
#
#   numMappers  M := numCores * 1.5
#   numReducers R := numCores max 4
#   java_Xmx       := 0.75 * (TotalRam / (numCores * 1.5) )
#   ulimit         := 3 * java_Xmx
#
# With 1.5*cores tasks taking up max heap, 75% of memory is occupied.  If your
# job is memory-bound on both map and reduce side, you *must* reduce the number
# of map and reduce tasks for that job to less than 1.5*cores together.  using
# mapred.max.maps.per.node and mapred.max.reduces.per.node, or by setting
# java_child_opts.
#
# It assumes EC2 instances with EBS-backed volumes
# If your cluster is heavily used and has many cores/machine (almost always running a full # of maps and reducers) turn down the number of mappers.
# If you typically run from S3 (fully I/O bound) increase the number of maps + reducers moderately.
# In both cases, adjust the memory settings accordingly.
#
#
# FIXME: The below parameters are calculated for each node.
#   The max_map_tasks and max_reduce_tasks settings apply per-node, no problem here
#   The remaining ones (java_child_opts, io_sort_mb, etc) are applied *per-job*:
#   if you launch your job from an m2.xlarge on a heterogeneous cluster, all of
#   the tasks will kick off with -Xmx4531m and so forth, regardless of the RAM
#   on that machine.
#
#
instance_type = node[:ec2] ? node[:ec2][:instance_type] : 'vsphere'
hadoop_performance_settings =
  case instance_type
  when 'm1.small'   then { :max_map_tasks =>  2, :max_reduce_tasks => 1, :java_child_opts =>  '-Xmx870m',                                                    :java_child_ulimit =>  2227200, :io_sort_factor => 10, :io_sort_mb => 160, }
  when 'c1.medium'  then { :max_map_tasks =>  3, :max_reduce_tasks => 2, :java_child_opts =>  '-Xmx870m',                                                    :java_child_ulimit =>  2227200, :io_sort_factor => 10, :io_sort_mb => 160, }
  when 'm1.large'   then { :max_map_tasks =>  3, :max_reduce_tasks => 2, :java_child_opts => '-Xmx2432m -XX:+UseCompressedOops -XX:MaxNewSize=200m -server', :java_child_ulimit =>  7471104, :io_sort_factor => 25, :io_sort_mb => 256, }
  when 'c1.xlarge'  then { :max_map_tasks => 10, :max_reduce_tasks => 4, :java_child_opts =>  '-Xmx870m',                                                    :java_child_ulimit =>  2227200, :io_sort_factor => 20, :io_sort_mb => 160, }
  when 'm1.xlarge'  then { :max_map_tasks =>  6, :max_reduce_tasks => 4, :java_child_opts => '-Xmx1920m -XX:+UseCompressedOops -XX:MaxNewSize=200m -server', :java_child_ulimit =>  5898240, :io_sort_factor => 25, :io_sort_mb => 256, }
  when 'm2.xlarge'  then { :max_map_tasks =>  4, :max_reduce_tasks => 2, :java_child_opts => '-Xmx4531m -XX:+UseCompressedOops -XX:MaxNewSize=200m -server', :java_child_ulimit => 13447987, :io_sort_factor => 32, :io_sort_mb => 256, }
  when 'm2.2xlarge' then { :max_map_tasks =>  6, :max_reduce_tasks => 4, :java_child_opts => '-Xmx4378m -XX:+UseCompressedOops -XX:MaxNewSize=200m -server', :java_child_ulimit => 13447987, :io_sort_factor => 32, :io_sort_mb => 256, }
  when 'm2.4xlarge' then { :max_map_tasks => 12, :max_reduce_tasks => 4, :java_child_opts => '-Xmx4378m -XX:+UseCompressedOops -XX:MaxNewSize=200m -server', :java_child_ulimit => 13447987, :io_sort_factor => 40, :io_sort_mb => 256, }
  when 'vsphere'
    cores        = node[:cpu][:total].to_i
    ram          = node[:memory][:total].to_i / 1000 # in MB
    n_mappers    = (2 + cores * 2/3).to_i
    n_reducers   = (2 + cores * 1/3).to_i

    roles_need_mem = ['hadoop_datanode', 'hadoop_tasktracker', 'hbase_regionserver', 'mapr_tasktracker']
    roles_num    = node.roles.select{|role| roles_need_mem.include?(role)}.size

    io_sort_mb = 100
    if ram > 4 * 1024
      io_sort_mb = 300
    end
    heap_size = (ram.to_f - 1024 - io_sort_mb * n_mappers - 1024 * roles_num * 0.6) / (n_mappers + n_reducers)
    heap_size    = [256, heap_size.to_i].max
    child_ulimit = 3 * heap_size * 1024
    { :max_map_tasks => n_mappers, :max_reduce_tasks => n_reducers, :java_child_opts => "-Xmx#{heap_size}m", :java_child_ulimit => child_ulimit, :io_sort_factor => 10, :io_sort_mb => io_sort_mb, :io_sort_record_percent => 0.14 }
  end

set[:yarn][:nm_resource_mem] = (0.8 * node[:memory][:total].to_i / 1024).to_i
set[:yarn][:am_resource_mem] = [1536, (0.3 * node[:memory][:total].to_i / 1024).to_i].max
hadoop_performance_settings.each{ |k,v| set[:hadoop][k] = v }
