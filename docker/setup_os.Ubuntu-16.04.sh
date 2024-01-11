#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y libgraphviz-perl libchart-gnuplot-perl
apt-get install -y --no-install-recommends curl python3 perl perl-doc \
                   sqlite3 libdbd-sqlite3-perl postgresql-client libdbd-pg-perl mysql-client libdbd-mysql-perl libdbi-perl \
                   libcapture-tiny-perl libdatetime-perl libjson-perl libproc-daemon-perl libemail-stuffer-perl\
                   libtest-exception-perl libtest-simple-perl libtest-warn-perl libtest-json-perl libtest-warnings-perl libtest-file-contents-perl libtest-perl-critic-perl \
                   libgetopt-argvfile-perl libbsd-resource-perl

# Java
apt-get install -y --no-install-recommends software-properties-common
add-apt-repository -y ppa:openjdk-r/ppa
apt-get update -y
apt-get install -y --no-install-recommends openjdk-12-jre-headless
dpkg-reconfigure ca-certificates-java
apt-get purge -y --auto-remove software-properties-common

## Useful for debugging
#apt-get install -y netcat.openbsd vim perl-doc iputils-ping net-tools apt-file

# Cleanup the cache to reduce the disk footprint
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Needed for Perl DBI
ln -s /usr/bin/mariadb_config /usr/bin/mysql_config

