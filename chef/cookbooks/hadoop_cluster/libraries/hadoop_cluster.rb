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

module HadoopCluster

  ## Service Dependencies in Hadoop/HBase Cluster ##
  # datanode depends on namenode; tasktracker depends on jobtracker; jobtracker depends on HDFS;
  # namenode depends on journalnodes in Namenode HA Cluster; journalnode depends on zookeeper nodes;
  # hbase master depends on zookeepers and HDFS; hbase regionserver depends on hbase master; etc.
  # So we need to call wait_for_xxx_service before starting yyy service if yyy depends on xxx.

  # whether the node itself has namenode role
  def is_namenode
    node.role?("hadoop_namenode")
  end

  # The namenode's hostname, or the local node's numeric ip if 'localhost' is given.
  def namenode_address
    if is_namenode or is_journalnode
      fqdn = fqdn_of_hdfs_network(node)
      if node[:provision][:fqdn].nil? or node[:provision][:fqdn] != fqdn
        node.set[:provision][:fqdn] = fqdn
        node.save
      end
      return fqdn
    end
    # if the user has specified the namenode ip, use it.
    namenode_ip_conf || provider_fqdn_for_role("hadoop_namenode")
  end

  def wait_for_namenode_service(in_ruby_block = true)
    return if is_namenode or is_journalnode or namenode_ip_conf
    run_in_ruby_block __method__, in_ruby_block do
      wait_for_service(node[:hadoop][:namenode_service_name])
    end
  end

  def namenode_port
    # if the user has specified the namenode port, use it.
    namenode_port_conf || node[:hadoop][:namenode_service_port]
  end

  # whether the node itself has journalnode role
  def is_journalnode
    node.role?("hadoop_journalnode")
  end

  # whether the node itself facet_index equal 0
  def is_primary_namenode
    node[:facet_index] == 0
  end

  def journalnodes_quorum
    servers = all_providers_fqdn_for_role("hadoop_journalnode")
    servers.collect { |ip| "#{ip}:#{node[:hadoop][:journalnode_service_port]}" }.join(";")
  end

  def wait_for_journalnodes_service(in_ruby_block = true)
    return if !node[:hadoop][:namenode_ha_enabled]
    return if is_journalnode

    run_in_ruby_block __method__, in_ruby_block do
      journalnode_count = all_nodes_count({"role" => "hadoop_journalnode"})
      wait_for_service(node[:hadoop][:journalnode_service_name], journalnode_count)
    end
  end

  def install_datanode_if_has_datanode_role
    include_recipe "hadoop_cluster::datanode" if node.role?("hadoop_datanode")
  end

  def install_namenode_if_has_namenode_role
    include_recipe "hadoop_cluster::namenode" if node.role?("hadoop_namenode")
  end

  def install_jobtracker_if_has_jobtracker_role
    include_recipe "hadoop_cluster::jobtracker" if node.role?("hadoop_jobtracker")
  end

  def install_resourcemanager_if_has_resourcemanager_role
    include_recipe "hadoop_cluster::resourcemanager" if node.role?("hadoop_resourcemanager")
  end

  # All facet names which have hadoop_namenode role
  def namenode_facet_names
    # the facet names will not change during bootstrap, so call Chef Search API only once.
    return @namenode_facet_names if @namenode_facet_names
    servers = all_nodes({"role" => "hadoop_namenode"})
    @namenode_facet_names = servers.map{ |server| facet_name_of_server(server) }.uniq.sort
  end

  def namenode_facet_addresses
    # the facet names and IP will not change during bootstrap, so call Chef Search API only once.
    return @namenode_facet_addresses if @namenode_facet_addresses
    facet_names = namenode_facet_names
    @namenode_facet_addresses = facet_names.map do | name |
      servers = all_nodes({"role" => "hadoop_namenode", "facet_name" => name}).uniq.sort
      {name => servers.map{ |server| ip_of_hdfs_network(server) }}
    end
  end

  # The cluster HDFS Namenode HA or federation is enabled if more than 1 node has hadoop_namenode role
  def cluster_has_hdfs_ha_or_federation
    servers = all_nodes({"role" => "hadoop_namenode"})
    servers.count > 1
  end

  # The cluster has only federation if namenode number equal group number which has hadoop_namenode role and namenode number more than 1
  def cluster_has_only_federation
    servers = all_nodes({"role" => "hadoop_namenode"})
    namenode_count = servers.count
    namenode_facet_count = servers.map{ |server| facet_name_of_server(server) }.uniq.count
    namenode_count > 1 and namenode_count == namenode_facet_count
  end

  # The node Namenode HA is enabled if more than 1 node has hadoop_namenode role in the same facet
  # This methond must be called and takes effect on the namenodes only
  def namenode_ha_enabled
    servers = all_nodes({"role" => "hadoop_namenode", "facet_name" => node[:facet_name]})
    servers.count > 1
  end

  # whether the node itself has secondarynamenode role
  def is_secondarynamenode
    node.role?("hadoop_secondarynamenode")
  end

  # whether the node itself has jobtracker role
  def is_jobtracker
    node.role?("hadoop_jobtracker")
  end

  # Find the node which has jobtracker role
  def jobtracker_node
    nodes = all_nodes({"role" => "hadoop_jobtracker"})
    (nodes and nodes.size > 0) ? nodes[0] : nil
  end

  # The jobtracker's hostname, or the local node's numeric ip if 'localhost' is given.
  def jobtracker_address
    return fqdn_of_mapred_network(node) if is_jobtracker
    ip = jobtracker_ip_conf
    if !ip
      jobtracker = jobtracker_node
      if jobtracker
        if is_namenode or is_secondarynamenode or is_journalnode
          # namenode and secondarynamenode don't require the jobtracker service is running
          ip = fqdn_of_mapred_network(jobtracker)
        else
          ip = provider_fqdn_for_role("hadoop_jobtracker")
        end
      else
        # return empty string if the cluster doesn't have a jobtracker (e.g. an HBase cluster)
        ip = ""
      end
    end
    ip
  end

  def wait_for_jobtracker_service(in_ruby_block = true)
    return if is_jobtracker or is_journalnode or jobtracker_ip_conf
    run_in_ruby_block __method__, in_ruby_block do
      wait_for_service(node[:hadoop][:jobtracker_service_name])
    end
  end

  def jobtracker_port
    # if the user has specified the jobtracker port, use it.
    jobtracker_port_conf || node[:hadoop][:jobtracker_service_port]
  end

  # The resourcemanager's hostname, or the local node's numeric ip if 'localhost' is given.
  # The resourcemanager in hadoop-0.23 is vary similar to the jobtracker in hadoop-0.20.
  def resourcemanager_address
    return fqdn_of_mapred_network(node) if is_resourcemanager
    ip = resourcemanager_ip_conf
    if !ip
      resmanager = resourcemanager_node
      if resmanager
        if is_namenode or is_secondarynamenode or is_journalnode
          # namenode and secondarynamenode don't require the resourcemanager service is running
          ip = fqdn_of_mapred_network(resmanager)
        else
          ip = provider_fqdn_for_role("hadoop_resourcemanager")
        end
      else
        # return empty string if the cluster doesn't have a resourcemanager (e.g. an Hadoop 2.x HBase cluster without YARN)
        ip = ""
      end
    end
    ip
  end

  def wait_for_resourcemanager_service(in_ruby_block = true)
    return if is_resourcemanager or is_journalnode or resourcemanager_ip_conf
    run_in_ruby_block __method__, in_ruby_block do
      wait_for_service(node[:hadoop][:resourcemanager_service_name])
    end
  end

  # whether the node itself has resourcemanager role
  def is_resourcemanager
    node.role?("hadoop_resourcemanager")
  end

  # Find the node which has resourcemanager role
  def resourcemanager_node
    nodes = all_nodes({"role" => "hadoop_resourcemanager"})
    (nodes and nodes.size > 0) ? nodes[0] : nil
  end

  # The erb template variables for generating Hadoop xml configuration files in $HADDOP_HOME/conf/
  def hadoop_template_variables
    vars = {
      :hadoop_home            => hadoop_home_dir,
      :hadoop_hdfs_home       => hadoop_hdfs_dir,
      :namenode_address       => namenode_address,
      :namenode_port          => namenode_port,
      :mapred_local_dirs      => formalize_dirs(mapred_local_dirs),
      :dfs_name_dirs          => formalize_dirs(dfs_name_dirs),
      :dfs_data_dirs          => formalize_dirs(dfs_data_dirs),
      :dfs_data_dirs_count    => dfs_data_dirs.size,
      :fs_checkpoint_dirs     => formalize_dirs(fs_checkpoint_dirs),
      :local_hadoop_dirs      => formalize_dirs(local_hadoop_dirs),
      :persistent_hadoop_dirs => formalize_dirs(persistent_hadoop_dirs),
      :all_cluster_volumes    => all_cluster_volumes,
      :mapred_bind_address    => fqdn_of_mapred_network(node),
      :hdfs_bind_address      => fqdn_of_hdfs_network(node),
      :hdfs_network_dev       => device_of_hdfs_network(node),
      :mapred_network_dev     => device_of_mapred_network(node)
    }
    if is_hadoop_yarn?
      vars[:resourcemanager_address] = resourcemanager_address
      vars[:yarn_local_dirs] = yarn_local_dirs.join(',')
      vars[:yarn_log_dirs] = yarn_log_dirs.join(',')
    else
      vars[:jobtracker_address] = jobtracker_address
      vars[:jobtracker_port] = jobtracker_port
    end

    if node[:hadoop][:cluster_has_hdfs_ha_or_federation]
      vars[:nameservices] = namenode_facet_names
      vars[:namenode_facets] = namenode_facet_addresses
    end

    if is_journalnode
      vars[:journalnode_edits_dir] = journalnode_edits_dir
    end

    if node[:hadoop][:namenode_ha_enabled]
      vars[:zookeepers_address] = zookeepers_quorum
      vars[:journalnodes_address] = journalnodes_quorum
    end

    vars
  end

  def hadoop_package package_name
    hadoop_major_version = node[:hadoop][:hadoop_handle]
    hadoop_home = hadoop_home_dir

    # Install from tarball
    if node[:hadoop][:install_from_tarball] then
      tarball_url = current_distro['hadoop']
      tarball_filename = tarball_url.split('/').last
      tarball_pkgname = tarball_filename.split('.tar.gz').first
      # component is one of ['hadoop', 'namenode', 'datanode', 'jobtracker', 'tasktracker', 'secondarynamenode']
      component = package_name.split('-').last

      if package_name == node[:hadoop][:packages][:hadoop][:name] then
        # install hadoop base package
        install_dir = [File.dirname(hadoop_home), tarball_pkgname].join('/')
        already_installed = File.exists?("#{install_dir}/lib")
        if already_installed then
          Chef::Log.info("#{tarball_filename} has already been installed. Will not re-install.")
          return
        end

        set_bootstrap_action(ACTION_INSTALL_PACKAGE, package_name, true)
        execute "install #{tarball_pkgname} from tarball" do
          not_if do already_installed end

          Chef::Log.info "start installing package #{tarball_pkgname} from tarball"
          command %Q{
            if [ ! -f /usr/local/src/#{tarball_filename} ]; then
              echo 'downloading tarball #{tarball_filename}'
              cd /usr/local/src/
              wget --tries=3 #{tarball_url} --ca-certificate=#{node[:ssl_ca_file_serengeti_httpd]}

              if [ $? -ne 0 ]; then
                echo 'Downloading tarball #{tarball_url} failed.'
                exit 1
              fi
            fi

            echo 'extract the tarball'
            prefix_dir=`dirname #{hadoop_home}`
            install_dir=$prefix_dir/#{tarball_pkgname}
            mkdir -p $install_dir
            cd $install_dir
            tar xzf /usr/local/src/#{tarball_filename} --strip-components=1
            if [ $? -ne 0 ]; then
              echo 'untar #{tarball_filename} failed. Is it a tar gzip file?'
              exit 2
            fi
            chown -R hdfs:hadoop $install_dir

            echo 'create symbolic links'
            ln -sf -T $install_dir $prefix_dir/#{hadoop_major_version}
            ln -sf -T $install_dir #{hadoop_home}
            mkdir -p /etc/#{hadoop_major_version}
            ln -sf -T #{hadoop_home}/conf /etc/#{hadoop_major_version}/conf
            ln -sf -T /etc/#{hadoop_major_version} /etc/hadoop

            # create hadoop logs directory, otherwise created by root:root with 755
            mkdir             #{hadoop_home}/logs
            chmod 777         #{hadoop_home}/logs
            chown hdfs:hadoop #{hadoop_home}/logs

            echo 'create hadoop command in /usr/bin/'
            cat <<EOF > /usr/bin/hadoop
#!/bin/sh
export HADOOP_HOME=#{hadoop_home}
exec #{hadoop_home}/bin/hadoop "\\$@"
EOF
            chmod 777 /usr/bin/hadoop
            test -d #{hadoop_home}
          }
        end
      end

      if ['namenode', 'datanode', 'jobtracker', 'tasktracker', 'secondarynamenode'].include?(component) then
        %W[hadoop-0.20-#{component}].each do |service_file|
          Chef::Log.info "installing #{service_file} as system service"
          template "/etc/init.d/#{service_file}" do
            owner "root"
            group "root"
            mode  "0755"
            variables( {:hadoop_version => hadoop_major_version} )
            source "#{service_file}.erb"
          end
        end
      end

      return
    end

    # Install from rpm/apt packages
    set_bootstrap_action(ACTION_INSTALL_PACKAGE, package_name, true)
    package_name.split.each do |name|
      package name do
        # Add retry for basic hadoop rpms which have big file size (about 20M).
        # The yum install command might timeout when the yum server is overloaded.
        retries 6
        retry_delay 5

        if node[:hadoop][:package_version] != 'current'
          version node[:hadoop][:package_version]
        end
      end
    end

    #FIXME this is a bug in Pivotal HD 1.0 alpha
    if is_pivotalhd_distro
      execute 'fix bug: service status always returns 0' do
        only_if 'ls /etc/init.d/hadoop-*'
        command %q{
for i in /etc/init.d/hadoop-*
do
  sed -i '/      RETVAL=$?/d' $i
done
        }
      end
    end
  end

  # Make a hadoop-owned directory
  def make_hadoop_dir dir, dir_owner="hadoop", dir_mode="0755"
    directory dir do
      owner    dir_owner
      group    "hadoop"
      mode     dir_mode
      action   :create
      recursive true
    end
  end

  # the execute provider can only support one "command" item, 
  # if there are multiple "command" items exist, only the last 
  # one take effect
  def ensure_hadoop_owns_hadoop_dirs dir, dir_owner, dir_mode="0755"
    execute "Make sure hadoop owns hadoop dirs" do
      command %Q{chown -R #{dir_owner}:hadoop #{dir} && chmod -R #{dir_mode} #{dir}}
      not_if{ (File.stat(dir).uid == dir_owner) && (File.stat(dir).gid == 300) }
    end
  end

  def ensure_yarn_dirs_stat dir, dir_mode="0755"
    execute "set yarn dirs stat" do
      command %Q{chown -R yarn:yarn #{dir} && chmod -R #{dir_mode} #{dir}}
    end
  end

  # log dir for hadoop daemons
  def real_hadoop_log_dir
    hadoop_log_dir_conf || local_hadoop_log_dir
  end

  def local_hadoop_log_dir
    dir = ""
    if node[:hadoop][:use_data_disk_as_log_vol]
      if node[:nfs_mapred_dirs].nil?
        dir = node[:disk][:hadoop_log_root_dir]
      else
        # discard NFS temporarily
        dir = node[:nfs_mapred_dirs].last
      end
    end
    if dir.nil? or dir == ""
      dir = "/mnt/hadoop"
    end
    File.join(dir, 'hadoop/log')
  end

  def yarn_system_log_dir
    dir = ""
    if node[:hadoop][:use_data_disk_as_log_vol]
      dir = node[:disk][:hadoop_log_root_dir]
    end
    if dir.nil? or dir == ""
      dir = "/mnt/hadoop"
    end
    File.join(dir, 'hadoop-yarn/log')
  end

  def local_hadoop_dirs
    dirs = node[:disk][:data_disks].map do |mount_point, device|
      mount_point + '/hadoop' if File.exists?(node[:disk][:disk_devices][device])
    end
    dirs.compact!
    dirs.unshift('/mnt/hadoop') if node[:hadoop][:use_root_as_scratch_vol]
    dirs.uniq
  end

  def persistent_hadoop_dirs
    dirs = local_hadoop_dirs
    dirs.unshift('/mnt/hadoop') if node[:hadoop][:use_root_as_persistent_vol]
    dirs.uniq
  end

  # The HDFS data. Spread out across persistent storage only
  def dfs_data_dirs
    persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/data')}
  end
  # The HDFS metadata. Keep this on two different volumes, at least one persistent
  def dfs_name_dirs
    dirs = persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/name')}
    unless node[:hadoop][:extra_nn_metadata_path].nil?
      dirs << File.join(node[:hadoop][:extra_nn_metadata_path].to_s, node[:cluster_name], 'hdfs/name')
    end
    dirs
  end
  # HDFS metadata checkpoint dir. Keep this on two different volumes, at least one persistent.
  def fs_checkpoint_dirs
    dirs = persistent_hadoop_dirs.map{|dir| File.join(dir, 'hdfs/secondary')}
    unless node[:hadoop][:extra_nn_metadata_path].nil?
      dirs << File.join(node[:hadoop][:extra_nn_metadata_path].to_s, node[:cluster_name], 'hdfs/secondary')
    end
    dirs
  end
  # Local storage during map-reduce jobs. Point at every local disk.
  def mapred_local_dirs
    if node[:nfs_mapred_dirs].nil?
      return local_hadoop_dirs.map{|dir| File.join(dir, 'mapred/local')}
    else
      return node[:nfs_mapred_dirs]
    end
  end

  def yarn_local_dirs
    local_hadoop_dirs.map{|dir| File.join(dir, 'yarn/local')}
  end

  def yarn_log_dirs
    local_hadoop_dirs.map{|dir| File.join(dir, 'yarn/log')}
  end

  def journalnode_edits_dir
    "/var/lib/journalnode"
  end

  # Hadoop 0.23 requires hadoop directory path in conf files to be in URI format
  def formalize_dirs dirs
    if is_hadoop_yarn?
      'file://' + dirs.join(',file://')
    else
      dirs.join(',')
    end
  end

  # return true if installing Hadoop 2.0 which includs HDFS2 and Hadoop YARN/MRv2
  # this flag will be set in the cluster role by Ironfan before running chef-client
  # default value is nil (i.e. Hadoop MRv1 cluster)
  def is_hadoop_yarn?
    # Ironfan can't tell whether it's a Hadoop 2.0 cluster when the cluster doesn't has nodes with hadoop_resourcemanager role.
    # e.g. a Hadoop HDFS2 + HBase cluster without YARN.
    if is_hadoop2_distro
      node.normal[:is_hadoop_yarn] = true
    end

    node[:is_hadoop_yarn]
  end

  # HADOOP_HOME
  def hadoop_home_dir
    node[:hadoop][:hadoop_home_dir]
  end

  # hadoop hdfs dir
  def hadoop_hdfs_dir
    node[:hadoop][:hadoop_hdfs_dir]
  end

  # hadoop mapreduce dir
  def hadoop_mapreduce_dir
    node[:hadoop][:hadoop_mapred_dir]
  end

  # hadoop conf dir
  def hadoop_conf_dir
    node[:hadoop][:hadoop_conf_dir]
  end

  def bin_hadoop_daemon_sh
    '/usr/lib/hadoop/bin/hadoop-daemon.sh'
  end

  def sbin_hadoop_daemon_sh
    '/usr/lib/hadoop/sbin/hadoop-daemon.sh'
  end

  def path_of_hadoop_daemon_sh
    File.exists?(bin_hadoop_daemon_sh) ? bin_hadoop_daemon_sh : sbin_hadoop_daemon_sh
  end

  # in Hadoop 0.23 hadoop-daemon.sh is in /usr/lib/hadoop/bin/, while in Hadoop 0.20 it's in /usr/lib/hadoop/sbin/
  def check_hadoop_daemon_sh
    from = bin_hadoop_daemon_sh
    target = sbin_hadoop_daemon_sh
    link(from) do
      not_if { File.exist?(from) }
      only_if { File.exist?(target) }
      to target
    end
  end

  # this is just a stub to prevent code broken
  def all_cluster_volumes
    nil
  end

  # Install VM level Namenode/Jobtracker HA provided by Hortonworks HMonitor
  def hadoop_ha_package component
    return if !is_hortonworks_hmonitor_enabled

    if ['namenode', 'jobtracker'].include?(component) then
      suffix = is_cdh4_distro ? '-cdh4' : ''
      pkg = "hmonitor#{suffix}-vsphere-#{component}-daemon"
      set_bootstrap_action(ACTION_INSTALL_PACKAGE, pkg, true)
      package pkg do
        action :install
      end

      # put libVMGuestAppMonitorNative.so in /usr/lib/hadoop/lib/native/, so hadoop daemons can find it.
      make_link('/usr/lib/hadoop/lib/native/libVMGuestAppMonitorNative.so', '/usr/lib/hadoop/monitor/libVMGuestAppMonitorNative.so')

      # generate configuration file for HMonitor HA service
      file = "vm-#{component}.xml"
      template_variables = hadoop_template_variables
      template_variables[:jobtracker_monitor_enabled] = is_jobtracker
      template "/usr/lib/hadoop/monitor/#{file}" do
        owner "root"
        mode "0644"
        variables(template_variables)
        source "#{file}.erb"
      end

      clear_bootstrap_action
    end
  end

  # Stop HMonitor Service
  def stop_ha_service svc
    return if !is_hortonworks_hmonitor_enabled

    service svc do
      action [ :disable, :stop ]
      supports :status => true, :restart => true
    end
  end

  def start_ha_service svc, delayed = false
    return if !is_hortonworks_hmonitor_enabled

    if delayed
      execute 'delay-starting-hmonitor-service' do
        command 'echo'
        notifies :start, resources("service[#{svc}]"), :delayed
      end
    else
      service svc do
        action [ :start ]
        supports :status => true, :restart => true
      end
    end
  end

  # Hortonworks HMonitor vSphere HA Kit can not monitor namenode service and resourcemanager service in Hadoop HDFS2 and YARN
  def is_hortonworks_hmonitor_enabled
    node[:hadoop][:ha_enabled] and (is_hadoop1_distro or is_cdh4_distro)
  end

  def is_hortonworks_hmonitor_namenode_enabled
    is_namenode and is_hortonworks_hmonitor_enabled and !is_cdh4_distro
  end

  # The Hortonworks HMonitor 1.1 has two monitor daemons: one for Namenode, the other for Jobtracker.
  # When the Namenode and Jobtracker run on the same machine, if the two monitor daemons are started,
  # they will send heartbeat respectively, thus either Namenode or Jobtracker is dead will not trigger vSphere HA.
  # So in this case, we need to config Namenode HMonitor to monitor Jobtracker as well.
  def is_hortonworks_hmonitor_jobtracker_enabled
    is_jobtracker and is_hortonworks_hmonitor_enabled and !is_hortonworks_hmonitor_namenode_enabled
  end

end

class Chef::Recipe
  include HadoopCluster
end

class Chef::Resource::Directory
  include HadoopCluster
end

class Chef::Resource::Service
  include HadoopCluster
end
