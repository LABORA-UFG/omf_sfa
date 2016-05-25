#!/bin/bash

git pull origin master
bundle exec ruby -I lib lib/omf-sfa/am/am_server.rb start