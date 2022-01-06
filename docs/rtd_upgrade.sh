#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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


# Bail out if anything goes wrong
set -e

# Restart from a clean state
rm -rf "$1"
mkdir -p "$1"
cd "$1"

echo ISSUE
cat /etc/issue
echo PERLVERSION
perl --version
mkdir packages
cd packages
# List of extra packages we need
apt-get download \
     libdbd-sqlite3-perl \
     libjson-xs-perl \
     libjson-perl \
     libcommon-sense-perl \
     libtypes-serialiser-perl \
     libxml-xpath-perl \
     libparse-recdescent-perl \
     libipc-run-perl \
     libio-pty-perl \
     libgraphviz-perl \
     doxypy \
     libproc-daemon-perl \

# manual download because rtd hasn't updated apt-cache
echo http://archive.ubuntu.com/ubuntu/pool/main/libd/libdbi-perl/libdbi-perl_1.640-1_amd64.deb \
  | xargs -n 1 curl -O

mkdir ../root
for i in *.deb; do dpkg -x "$i" ../root/; done

git clone --branch master --depth 1 https://github.com/Ensembl/ensembl.git ../ensembl
git clone --branch version/2.6 --depth 1 https://github.com/Ensembl/ensembl-hive-docker-swarm.git ../ensembl-hive-docker-swarm

rm -f ../../../contrib/docker-swarm
ln -s "$1/ensembl-hive-docker-swarm/docs" ../../../contrib/docker-swarm
