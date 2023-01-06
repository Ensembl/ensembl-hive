#!/usr/bin/env perl
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


use strict;
use warnings;

use Data::Dumper;

use Test::More;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_urls run_sql_on_db);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $ehive_test_pipeline_urls = get_test_urls();

foreach my $pipeline_url (@$ehive_test_pipeline_urls) {

subtest 'Test on '.$pipeline_url, sub {
    plan tests => 20;

init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf', $pipeline_url);

my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );
my $ana_a       = $hive_dba->get_AnalysisAdaptor;
my $job_a       = $hive_dba->get_AnalysisJobAdaptor;
my $dfr_a       = $hive_dba->get_DataflowRuleAdaptor;
my $ada_a       = $hive_dba->get_AnalysisDataAdaptor;

is($ana_a->count_all(), 3, 'There are 3 analyses in the pipeline');
is($ana_a->count_all_by_logic_name('take_b_apart'), 1, 'But only 1 "take_b_apart"');
my $take_b_apart_analysis = $ana_a->fetch_by_logic_name('take_b_apart');

my $n_from_1 = $dfr_a->count_all_by_from_analysis_id($take_b_apart_analysis->dbID);
is($n_from_1, 2, '2 dataflow-rules starting from this analysis_id');
my $matching_analyses = $dfr_a->fetch_all_by_from_analysis_id($take_b_apart_analysis->dbID);
is(scalar(@$matching_analyses), 2, '2 dataflow-rules starting from this analysis_id');

my $n_from_1_on_2 = $dfr_a->count_all_by_from_analysis_id_AND_branch_code($take_b_apart_analysis->dbID, 2);
is($n_from_1_on_2, 1, '1 dataflow-rule starting from this analysis_id on this branch');
$matching_analyses = $dfr_a->fetch_all_by_from_analysis_id_AND_branch_code($take_b_apart_analysis->dbID, 2);
is(scalar(@$matching_analyses), 1, '1 dataflow-rule starting from this analysis_id on this branch');

is($dfr_a->count_all_by_branch_code(1), 3, 'There are 2 #1 branches in the pipeline');

is_deeply($job_a->count_all_HASHED_FROM_status(), { 'READY' => 2 }, 'There are two jobs and both are READY');
is_deeply($job_a->count_all_HASHED_FROM_status_AND_job_id(), { 'READY' => { '1' => 1, '2' => 1 } }, 'They have dbIDs 1 and 2');
is_deeply($job_a->count_all_by_analysis_id_HASHED_FROM_status(1), { 'READY' => 2 }, 'They both belong to the analysis with dbID=1');

my $long_input_id = sprintf('{ "long_param" => "%s" }', 'tmp' x 1000);
my $new_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => $long_input_id,
    'analysis_id'   => 1,
);

# Test the overflow to the analysis_data table
is($ada_a->count_all(), 0, "Nothing in the analysis_data table (yet)");
$job_a->store($new_job);
is($ada_a->count_all(), 1, "1 entry in the analysis_data table");

is($ada_a->fetch_by_data_to_analysis_data_id('unmatched input_id'), undef, 'fetch_by_data_to_analysis_data_id() returns undef when it cannot find the input_id');
my $ext_data_id = $ada_a->fetch_by_data_to_analysis_data_id($long_input_id);
is($ext_data_id, 1, 'analysis_data_id starts at 1');

my $another_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => $long_input_id,
    'analysis_id'   => 2,
);

$job_a->store($another_job);
is($ada_a->count_all(), 1, "still 1 entry in the analysis_data table");

$hive_dba->dbc->disconnect_if_idle();
run_sql_on_db($pipeline_url, 'DROP DATABASE');

}
}

done_testing();

