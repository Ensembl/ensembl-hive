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


set -e

# NOTE: buildDeps may have to be extended to include some lib*-dev packages
#       such as libmariadb-client-lgpl-dev libpq-dev libsqlite3-dev libexpat1-dev
buildDeps='
  cpanminus
  build-essential
'
apt-get update -y
apt-get install -y $buildDeps

for arg
do
	[ -f "$arg/cpanfile" ] && cpanm --installdeps --with-recommends "$arg"
done
# Cleanup the cache and remove the build dependencies to reduce the disk footprint
rm -rf /var/lib/apt/lists/* /root/.cpanm
apt-get purge -y --auto-remove $buildDeps

