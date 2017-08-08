#!/bin/sh

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

