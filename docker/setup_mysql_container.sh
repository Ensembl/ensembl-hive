#!/bin/sh
# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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


# Create a MySQL 5.5 server in a Docker container with a user able to run Hive pipelines:

export MYSQL_USER=ensrw
export MYSQL_PASSWORD=ensrw_password

docker run --rm --name mysql_5_5 -e MYSQL_USER -e MYSQL_PASSWORD -e MYSQL_DATABASE=% -e MYSQL_RANDOM_ROOT_PASSWORD=1 -p 8806:3306 -d mysql/mysql-server:5.5

export EHIVE_URL=mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${HOSTNAME}:8806/test_long_mult_inside

init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf --pipeline_url $EHIVE_URL

runWorker.pl -url $EHIVE_URL

db_cmd.pl -url $EHIVE_URL


	# OR EVEN:
docker run -it ensemblorg/ensembl-hive  init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $EHIVE_URL
docker run -it ensemblorg/ensembl-hive  beekeeper.pl -url $EHIVE_URL

