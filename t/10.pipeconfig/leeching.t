#!/usr/bin/env perl

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


use strict;
use warnings;

use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker get_test_url_or_die safe_drop_database);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

init_pipeline(
    'Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LeachingTest_conf',
    $pipeline_url,
);

my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
    -url                        => $pipeline_url,
    -disconnect_when_inactive   => 1,
);

runWorker($pipeline_url, [ -analyses_pattern => 'start' ]);
runWorker($pipeline_url, [ -analyses_pattern => 'factory' ]);

my $analyses_coll   = $pipeline->collection_of('Analysis');
my $fan_analysis    = $analyses_coll->find_one_by( 'logic_name' => 'fan' );

my $hive_dba            = $pipeline->hive_dba;
my $job_adaptor         = $hive_dba->get_AnalysisJobAdaptor;
my $semaphore_adaptor   = $hive_dba->get_SemaphoreAdaptor;
my @semaphores          = @{ $semaphore_adaptor->fetch_all() };

is(scalar(@semaphores), 1, 'There has to be only one semaphore');

my $fan_job_count       = $job_adaptor->count_all_by_analysis_id( $fan_analysis->dbID );
my $correct_count       = 7;

is($fan_job_count, $correct_count, "The number of fan jobs is correct ($fan_job_count == $correct_count)");

my $semaphore           = shift @semaphores;

is($semaphore->local_jobs_counter, $fan_job_count, 'All the fan jobs share the same semaphore');

runWorker($pipeline_url, [ -analyses_pattern => 'fan' ]);
runWorker($pipeline_url, [ -analyses_pattern => 'funnel' ]);

@semaphores          = @{ $semaphore_adaptor->fetch_all() };
is(scalar(@semaphores), 2, 'There are now two semaphores');

my $jobs             = $job_adaptor->fetch_all_by_analysis_id_status([$fan_analysis], 'READY');
is(scalar(@$jobs), 1, 'The fan has an extra job');
$jobs                = $job_adaptor->fetch_all_by_analysis_id_status([$analyses_coll->find_one_by( 'logic_name' => 'aggregator' )]);
is(scalar(@$jobs), 1, 'Still only one aggregator job');
is($jobs->[0]->status, 'SEMAPHORED', 'The aggregator is now SEMAPHORED');

safe_drop_database( $hive_dba );

done_testing();

