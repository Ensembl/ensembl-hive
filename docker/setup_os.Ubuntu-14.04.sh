#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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

apt-get update
apt-get install -y curl perl-doc \
                   sqlite3 libdbd-sqlite3-perl postgresql-client libdbd-pg-perl mysql-client libdbd-mysql-perl libdbi-perl \
                   libcapture-tiny-perl libdatetime-perl libhtml-parser-perl libjson-perl libemail-mime-perl libemail-sender-perl libemail-simple-perl \
                   libtest-exception-perl libtest-simple-perl libtest-warn-perl libtest-warnings-perl libtest-file-contents-perl libtest-perl-critic-perl libtest-fatal-perl libgraphviz-perl \
                   libgetopt-argvfile-perl libchart-gnuplot-perl libbsd-resource-perl

## Useful for debugging
#apt-get install -y netcat.openbsd vim perl-doc iputils-ping net-tools apt-file

apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

