maintainer       "Philip (flip) Kromer - Infochimps, Inc"
maintainer_email "coders@infochimps.com"
license          "Apache 2.0"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "3.0.5"

description      "Installs/Configures hive"

depends          "java"
depends          "hadoop_cluster"
depends          "install_from"
depends          "postgresql"

recipe           "hive::default",                      "Base configuration for hive"
recipe           "hive::postgresql_metastore",         "Configuration for postgresql metastore"
recipe           "hive::server",                       "Configuration for hive server"

%w[ debian ubuntu ].each do |os|
  supports os
end
