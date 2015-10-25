maintainer        "Opscode, Inc."
maintainer_email  "cookbooks@opscode.com"
license           "Apache 2.0"
description       "Installs java via openjdk."
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           "2.0"
%w{ debian ubuntu fedora }.each do |os|
  supports os
end
depends 'apt'
recipe "java", "Installs openjdk to provide Java"
