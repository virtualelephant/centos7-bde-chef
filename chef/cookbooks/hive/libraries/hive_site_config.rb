#
#   Copyright (c) 2012-2014 VMware, Inc. All Rights Reserved.
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

module HiveSiteConfiguration

  def update_hive_config
    directory "#{node[:hive][:home_dir]}/conf" do
      mode 0775
    end

    run_in_ruby_block('update_hive_config_ruby_block') do
      property_kvs = {}
      property_kvs["javax.jdo.option.ConnectionURL"]="jdbc:postgresql://#{node[:ipaddress]}:5432/#{node[:hive][:metastore_db]}"
      property_kvs["javax.jdo.option.ConnectionDriverName"]="org.postgresql.Driver"
      property_kvs["javax.jdo.option.ConnectionUserName"] = "#{node[:hive][:metastore_user]}"
      property_kvs["javax.jdo.option.ConnectionPassword"] = "#{node[:postgresql][:password][:postgres]}"
      property_kvs["hive.metastore.uris"] = ""
      property_kvs["hive.hwi.war.file"] = "/usr/lib/hive/lib/hive-hwi.jar" if is_intel_distro # fix bug of intel distro
      output = generate_hadoop_xml_conf("#{node[:hive][:home_dir]}/conf/hive-site.xml", property_kvs)
      File.open("#{node[:hive][:home_dir]}/conf/hive-site.xml", "w") { |f| f.write(output) }
    end
  end

  def update_hive_version
    hive_version_file = "#{node[:hive][:home_dir]}/version"
    return if File.exist?(hive_version_file)

    if node[:hadoop][:install_from_tarball] then
      tarball_url = current_distro['hive']
      hive_file_name = tarball_url[tarball_url.rindex("/")+1..-1]
      version_reg = /(\d+\.\d+\.\d+)/
      matched_version = version_reg.match(hive_file_name);
      if matched_version
        hive_version = matched_version[0]
        node.normal[:hive][:version] = hive_version
        node.save
      end
      save_hive_version_to_file(hive_version_file)
    else
      run_in_ruby_block('update_hive_version') do
        hive_file_name = `rpm -q hive`
        version_reg = /(\d+\.\d+\.\d+)/
        matched_version = version_reg.match(hive_file_name);
        if matched_version
          hive_version = matched_version[0]
          node.normal[:hive][:version] = hive_version
          node.save
        end
        save_hive_version_to_file(hive_version_file)
      end 
    end
  end

  protected

  # save the version to a file
  def save_hive_version_to_file(file)
    system("echo #{node[:hive][:version]} > #{file}")
  end

end

class Chef::Recipe
  include HiveSiteConfiguration
end
