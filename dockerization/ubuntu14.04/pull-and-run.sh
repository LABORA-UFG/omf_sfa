#!/bin/bash

git pull origin master
bundle exec ruby -I lib lib/omf-sfa/am/am_server.rb start
/root/omf_sfa/bin/create_resource -t node -c /root/omf_sfa/bin/conf.yaml -i /root/resources.json