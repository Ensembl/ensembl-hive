#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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
use Data::Dumper;
use Test::JSON;

use Capture::Tiny ':all';
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper get_test_url_or_die run_sql_on_db tweak_pipeline);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

    # Starting a first set of checks with a "GCPct" pipeline

    init_pipeline('Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LongWorker_conf', $pipeline_url);

    my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

    # Check that -sync runs, puts one entry in the beekeeper table, and finishes with LOOP_LIMIT
    beekeeper($pipeline_url, ['-sync']);
    my $beekeeper_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'beekeeper');

    # Check that -run puts one additional in the beekeeper table, it loops once,
    # and finishes with LOOP_LIMIT
    beekeeper($pipeline_url, ['-run', '-meadow_type' => 'LOCAL', -job_limit => 1]);

    my $stdout = capture_stdout {
        tweak_pipeline($pipeline_url, ["-SHOW" => "analysis[perform_cmd].resource_class"])
    };
    is_valid_json $stdout;
  #  is($stdout, qq{Message 1\nMessage 7\n}, 'init_pipeline output');

    sleep(10); # give worker a bit of time to seed longrunning jobs

    beekeeper($pipeline_url, ['-run', -analyses_pattern => 'longrunning', -meadow_type => 'LOCAL', -job_limit => 1]);

    sleep(10); # give workers time to start

    my $worker_nta = $hive_dba->get_NakedTableAdaptor('table_name' => 'worker');

    sleep(10); # give workers a bit of time to die

    $hive_dba->dbc->disconnect_if_idle();
    run_sql_on_db($pipeline_url, 'DROP DATABASE');

done_testing();
