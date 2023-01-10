#!/bin/bash

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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

# This is a farm-specific manual test driver for our stress-test pipeline.
# It is supposed to submit many workers that will cause deadlocks in the database.


if [ -z "$1" ]; then
    echo "Please provide pipeline_url as the only command line parameter"
    exit 1;
fi

pipeline_url="$1"

init_pipeline.pl TestPipeConfig/SemaCounterOverload_conf.pm -pipeline_url $pipeline_url -hive_force_init 1

runWorker.pl -url $pipeline_url

runWorker.pl -url $pipeline_url

beekeeper.pl -url $pipeline_url -submit_workers_max 300 -run

echo "The workers have been submitted, please check the database $pipeline_url manually and don't forget to drop it afterwards"

