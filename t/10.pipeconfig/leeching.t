#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker get_test_url_or_die);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

my $url = init_pipeline(
    'Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LeachingTest_conf',
    [-pipeline_url => $pipeline_url, -hive_force_init => 1],
);

my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
    -url                        => $url,
    -disconnect_when_inactive   => 1,
);

runWorker($pipeline);   # 'start' analysis
runWorker($pipeline);   # 'factory' analysis

my $analyses_coll   = $pipeline->collection_of('Analysis');
my $fan_analysis    = $analyses_coll->find_one_by( 'logic_name' => 'fan' );
my $funnel_analysis = $analyses_coll->find_one_by( 'logic_name' => 'funnel' );

my $hive_dba        = $pipeline->hive_dba;
my $job_adaptor     = $hive_dba->get_AnalysisJobAdaptor;
my @funnel_jobs     = @{ $job_adaptor->fetch_all_by_analysis_id( $funnel_analysis->dbID ) };

is(scalar(@funnel_jobs), 1, 'There has to be only one funnel job');

my $funnel_job      = shift @funnel_jobs;
my $fan_job_count   = $job_adaptor->count_all_by_analysis_id( $fan_analysis->dbID );

is($funnel_job->semaphore_count, $fan_job_count, 'All the fan jobs ('.$fan_job_count.') share the same funnel');

$hive_dba->dbc->disconnect_if_idle();
system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );

done_testing();

