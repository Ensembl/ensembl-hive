#!/bin/sh

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
