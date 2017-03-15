#!/bin/bash

# Generate all those snapshots in a deterministic way:


export PIPELINE_URL=sqlite:///lg4_long_mult.sqlite
export VJ_OPTIONS="-values"

init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $PIPELINE_URL -take_time 0 -hive_force_init 1 

export NUM=01; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 1
beekeeper.pl -url $PIPELINE_URL -analyses_pattern add_together -sync

export NUM=02; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -analyses_pattern take_b_apart
beekeeper.pl -url $PIPELINE_URL -analyses_pattern add_together -sync

export NUM=03; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 4

export NUM=04; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 10
runWorker.pl -url $PIPELINE_URL -job_id 11

export NUM=05; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 5
runWorker.pl -url $PIPELINE_URL -job_id 6

export NUM=06; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 8
runWorker.pl -url $PIPELINE_URL -job_id 12
beekeeper.pl -url $PIPELINE_URL -analyses_pattern add_together -sync

export NUM=07; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 9
beekeeper.pl -url $PIPELINE_URL -analyses_pattern add_together -sync

export NUM=08; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 7
beekeeper.pl -url $PIPELINE_URL -sync

export NUM=09; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

runWorker.pl -url $PIPELINE_URL -job_id 3
beekeeper.pl -url $PIPELINE_URL -sync

export NUM=10; visualize_jobs.pl -url $PIPELINE_URL $VJ_OPTIONS -out long_mult_jobs_${NUM}.png ; generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${NUM}.png

