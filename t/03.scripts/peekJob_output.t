#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

use Capture::Tiny ':all';
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_url_or_die peekJob);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

# Starting a first set of checks with a "GCPct" pipeline

init_pipeline('Bio::EnsEMBL::Hive::Examples::FailureTest::PipeConfig::FailureTest_conf', $pipeline_url);

my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

my $stdout = capture_stdout {
    peekJob($pipeline_url, ["-job_id" => 1]);
};
$stdout =~ s/\s+//g;
my $exp_stdout = "%unsubstituted_param_hash[Analysisgenerate_jobs(1)Job1]=('column_names'=>['value'],'inputlist'=>'#expr([0..#job_count#-1])expr#','job_count'=>10);";
is( $stdout, $exp_stdout, 'Correct params reported' );

done_testing();
