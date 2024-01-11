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

use Data::Dumper;

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline run_sql_on_db get_test_urls);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $ehive_test_pipeline_urls = get_test_urls();

foreach my $pipeline_url (@$ehive_test_pipeline_urls) {

  subtest 'Test on '.$pipeline_url, sub {

    init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf', $pipeline_url);
    my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    my $ref_job     = $job_adaptor->fetch_all()->[0];

    ok($ref_job, 'Could fetch a reference job');

    my %job_param   = (
        'analysis'      => $ref_job->analysis,
        'input_id'      => '{"a" => 3}',
    );

    my $new_job1        = Bio::EnsEMBL::Hive::AnalysisJob->new(%job_param);
    my ($j1, $stored1)  = $job_adaptor->store($new_job1);

    ok($stored1, 'A new job could be stored');

    lives_ok( sub {
        my $new_job2        = Bio::EnsEMBL::Hive::AnalysisJob->new(%job_param);
        my ($j2, $stored2)  = $job_adaptor->store($new_job2);
        ok(!$stored2, 'A copy of the job was *not* stored (as expected)');
    }, 'Can survive the insertion of a duplicated job' );

    $hive_dba->dbc->disconnect_if_idle();
    run_sql_on_db($pipeline_url, 'DROP DATABASE');

  }
}

done_testing();

