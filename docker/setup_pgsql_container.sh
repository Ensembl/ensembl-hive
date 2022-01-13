#!/bin/sh
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


# Create a PostgreSQL 9.5 server in a Docker container with a user able to run Hive pipelines:

export POSTGRES_USER=ensrw
export POSTGRES_PASSWORD=ensrw_password

docker run --name postgres_9_5 -e POSTGRES_USER -e POSTGRES_PASSWORD -p 8432:5432 -d postgres:9.5

export EHIVE_URL=pgsql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${HOSTNAME}:8432/test_long_mult_inside

# NB!!! The first connection to port 8432 takes about a minute (?!?!?!), the rest seems to run smoothly

init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf --pipeline_url $EHIVE_URL

runWorker.pl -url $EHIVE_URL

db_cmd.pl -url $EHIVE_URL

    # OR EVEN:
    docker run -it ensemblorg/ensembl-hive  init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $EHIVE_URL
    docker run -it ensemblorg/ensembl-hive  beekeeper.pl -url $EHIVE_URL
