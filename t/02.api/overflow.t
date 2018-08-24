#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2018] EMBL-European Bioinformatics Institute
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

use Test::More tests => 18;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::ResourceClass;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $dir = tempdir CLEANUP => 1;
chdir $dir;

my $pipeline_url      = 'sqlite:///ehive_test_pipeline_db';

my $hive_dba    = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf', $pipeline_url, [-hive_force_init => 1]);

my $job_a       = $hive_dba->get_AnalysisJobAdaptor;
my $rcl_a       = $hive_dba->get_ResourceClassAdaptor;
my $rde_a       = $hive_dba->get_ResourceDescriptionAdaptor;
my $dfr_a       = $hive_dba->get_DataflowRuleAdaptor;
my $ada_a       = $hive_dba->get_AnalysisDataAdaptor;
my $acu_a       = $hive_dba->get_AccumulatorAdaptor;
my $acr_a       = $hive_dba->get_AnalysisCtrlRuleAdaptor;
my $ana_a       = $hive_dba->get_AnalysisAdaptor;

my $long_input_id = sprintf('{ "long_param" => "%s" }', 'tmp' x 1000);
my $new_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => $long_input_id,
    'analysis_id'   => 1,
);

# Test the overflow into the analysis_data table
# Test overflow for input_id
is($ada_a->count_all(), 0, "Nothing in the analysis_data table (yet)");

$job_a->store($new_job);
is($ada_a->count_all(), 1, "1 entry in the analysis_data table");

is($ada_a->fetch_by_data_TO_analysis_data_id('unmatched input_id'), undef, 'fetch_by_data_to_analysis_data_id() returns undef when it cannot find the input_id');
my $ext_data_id = $ada_a->fetch_by_data_TO_analysis_data_id($long_input_id);
is($ext_data_id, 1, 'analysis_data_id starts at 1');

my $fan_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => $long_input_id,
    'analysis_id'   => 2,
);

$job_a->store($fan_job);
is($ada_a->count_all(), 1, "still 1 entry in the analysis_data table");

# Test overflow for resource description args

Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->init_collections();
my $new_rc = Bio::EnsEMBL::Hive::ResourceClass->add_new_or_update(
    'name' => 'testresourceclass',
);

my $long_sca = 'sc' x 129;
my $long_wca = 'wc' x 129;
my $new_rd = Bio::EnsEMBL::Hive::ResourceDescription->add_new_or_update(
    'resource_class'      => $new_rc,
    'meadow_type'         => 'test_meadow',
    'submission_cmd_args' => $long_sca,
    'worker_cmd_args'     => $long_wca,
);

$rcl_a->store($new_rc);
$rde_a->store($new_rd);
is($ada_a->count_all(), 3, "New resource description overflowed two entries to analysis_data, total 3");

# Test overflow for to_analysis_urls

my $long_struct_name = 'ta' x 129;
my $long_to_analysis_url = ':////accu?' . $long_struct_name;
my $new_dfr = Bio::EnsEMBL::Hive::DataflowRule->add_new_or_update(
    'from_analysis'     => $ana_a->fetch_by_dbID(1),
    'to_analysis_url'   => $long_to_analysis_url,
    'branch_code'       => 3,
);

$dfr_a->store($new_dfr);
is($ada_a->count_all(), 4, "New to_analysis_url overflowed an entry to analysis_data, total 4");

# Test overflow for condition analysis urls

my $long_cau = 'cau' x 86;
my $ctrled_analysis_id = 1;
my $new_acr = Bio::EnsEMBL::Hive::AnalysisCtrlRule->add_new_or_update(
    'condition_analysis_url' => $long_cau,
    'ctrled_analysis'     => $ana_a->fetch_by_dbID($ctrled_analysis_id),
);

$acr_a->store($new_acr);
is($ada_a->count_all(), 5, "New condition_analysis_url overflowed an entry to analysis_data, total 5");

# Test overflow for accu key_signatures
# Note: AccumulatorAdaptor will complain if storing an accu without a proper fan job
# and semaphored funnel job

my $accu_funnel_job =  Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => {},
    'analysis_id'   => 3,
);
$job_a->store($accu_funnel_job);

my $accu_fan_job =  Bio::EnsEMBL::Hive::AnalysisJob->new(
    'input_id'      => {},
    'analysis_id'   => 2,
    'semaphored_job_id' => $accu_funnel_job->dbID,
);
$job_a->store($accu_fan_job);

my $new_accu = Bio::EnsEMBL::Hive::Accumulator->new(
    adaptor            => $acu_a,
    struct_name        => $long_struct_name,
    signature_template => '{key}',
);

my $long_key_signature = 'ks' x 129;
my $long_output_id = [ { 'key' => $long_key_signature,
                         $long_struct_name => 1, } ];
$new_accu->dataflow(
    $long_output_id,
    $accu_fan_job,
);

is($ada_a->count_all(), 7, "Overflow for long struct_name and key_signature in accu");

# Test retrieval of overflow data

my $fetched_rds = $rde_a->fetch_all();
my $rd_with_long_args;
foreach my $fetched_rd (@$fetched_rds) {
    if ($fetched_rd->resource_class_id() == $new_rc->dbID) {
        $rd_with_long_args = $fetched_rd;
    }
}

is($rd_with_long_args->submission_cmd_args, $long_sca, "Retrieved long submission_cmd_args");
is($rd_with_long_args->worker_cmd_args, $long_wca, "Retrieved long worker_cmd_args");

my $fetched_dfr = $dfr_a->fetch_by_dbID($new_dfr->dbID);
is ($fetched_dfr->to_analysis_url, $long_to_analysis_url, "Retrieved long to_analysis_url");

my $fetched_acr = $acr_a->fetch_by_ctrled_analysis_id($ctrled_analysis_id);
is ($fetched_acr->condition_analysis_url, $long_cau, "Retrieved long condition_analysis_url");

# $fetched_accu_structures->{$receiving_job_id}->{$struct_name}->{$key_signature} = value
my $fetched_accu_structures = $acu_a->fetch_structures_for_job_ids($accu_funnel_job->dbID);
my $fetched_accu_hash = $fetched_accu_structures->{$accu_funnel_job->dbID};
my $fetched_struct_name = (keys(%$fetched_accu_hash))[0];
my $fetched_key_signature = (keys(%$fetched_accu_hash->{$fetched_struct_name}))[0];

is ($fetched_struct_name, $long_struct_name, "fetched long struct_name from accu");
is ($fetched_key_signature, $long_key_signature, "fetched long key_signature from accu");

done_testing();
