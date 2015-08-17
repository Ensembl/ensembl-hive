#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

use Data::Dumper;
use File::Temp qw{tempdir};

use Test::More tests => 12;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $dir = tempdir CLEANUP => 1;
chdir $dir;

my $pipeline_url      = 'sqlite:///ehive_test_pipeline_db';

my $url         = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf', [-pipeline_url => $pipeline_url, -hive_force_init => 1]);

my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
    -url                        => $url,
    -disconnect_when_inactive   => 1,
);

my $hive_dba    = $pipeline->hive_dba;
my $ana_a       = $hive_dba->get_AnalysisAdaptor;
my $job_a       = $hive_dba->get_AnalysisJobAdaptor;
my $dfr_a       = $hive_dba->get_DataflowRuleAdaptor;

is($ana_a->count_all(), 3, 'There are 3 analyses in the pipeline');
is($ana_a->count_all_by_logic_name('take_b_apart'), 1, 'But only 1 "take_b_apart"');
my $take_b_apart_analysis = $hive_dba->get_AnalysisAdaptor->fetch_by_logic_name('take_b_apart');

my $n_from_1 = $dfr_a->count_all_by_from_analysis_id($take_b_apart_analysis->dbID);
is($n_from_1, 2, '2 dataflow-rules starting from this analysis_id');
my $matching_analyses = $dfr_a->fetch_all_by_from_analysis_id($take_b_apart_analysis->dbID);
is(scalar(@$matching_analyses), 2, '2 dataflow-rules starting from this analysis_id');

my $n_from_1_on_2 = $dfr_a->count_all_by_from_analysis_id_AND_branch_code($take_b_apart_analysis->dbID, 2);
is($n_from_1_on_2, 1, '1 dataflow-rule starting from this analysis_id on this branch');
$matching_analyses = $dfr_a->fetch_all_by_from_analysis_id_AND_branch_code($take_b_apart_analysis->dbID, 2);
is(scalar(@$matching_analyses), 1, '1 dataflow-rule starting from this analysis_id on this branch');

#is($matching_analyses->[0]->logic_name, $take_b_apart_analysis->logic_name, 'Correct logic_name');

is($dfr_a->count_all_by_branch_code(1), 3, 'There are 2 #1 branches in the pipeline');

is_deeply($job_a->count_all_HASHED_FROM_status(), { 'READY' => 2 }, 'There are two jobs and both are READY');
is_deeply($job_a->count_all_HASHED_FROM_status_AND_job_id(), { 'READY' => { '1' => 1, '2' => 1 } }, 'They have dbIDs 1 and 2');
is_deeply($job_a->count_all_by_analysis_id_HASHED_FROM_status(1), { 'READY' => 2 }, 'They both belong to the analysis with dbID=1');

done_testing();

