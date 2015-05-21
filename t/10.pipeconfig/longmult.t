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

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $dir = tempdir CLEANUP => 1;
chdir $dir;

my $ehive_test_pipeline_urls = $ENV{'EHIVE_TEST_PIPELINE_URLS'} || 'sqlite:///ehive_test_pipeline_db';
my @pipeline_urls = split( /[\s,]+/, $ehive_test_pipeline_urls ) ;

foreach my $long_mult_version (qw(LongMult_conf LongMultSt_conf LongMultWf_conf LongMultSt_pyconf)) {

warn "\nInitializing the $long_mult_version pipeline ...\n\n";

    foreach my $pipeline_url (@pipeline_urls) {
        my $hive_dba = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::'.$long_mult_version, [-pipeline_url => $pipeline_url, -hive_force_init => 1]);
        my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;

        # First run a single worker in this process
        runWorker($hive_dba, { can_respecialize => 1 });
        is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');

        # Let's now try the combination of end-user scripts: seed_pipeline + beekeeper
        {
            my @seed_pipeline_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/seed_pipeline.pl', -url => $hive_dba->dbc->url, -logic_name => 'take_b_apart', -input_id => '{"a_multiplier" => 2222222222, "b_multiplier" => 3434343434}');
            my @beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $hive_dba->dbc->url, -sleep => 0.1, '-loop', '-local');

            # beekeeper can take a while and has its own DBConnection, it
            # is better to close ours to avoid "MySQL server has gone away"
            $hive_dba->dbc->disconnect_if_idle;

            system(@seed_pipeline_cmd);
            ok(!$?, 'seed_pipeline exited with the return code 0');
            is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 1, 'There are new jobs to run');

            system(@beekeeper_cmd);
            ok(!$?, 'beekeeper exited with the return code 0');
            is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');
        }

        my $results = $hive_dba->dbc->db_handle->selectall_arrayref('SELECT * FROM final_result');
        is(scalar(@$results), 3, 'There are exactly 3 results');
        ok($_->[0]*$_->[1] eq $_->[2], sprintf("%s*%s=%s", $_->[0], $_->[1], $_->[0]*$_->[1])) for @$results;

            # disconnect to be able to drop the database (some drivers like PostgreSQL do not like dropping connected databases):
        $hive_dba->dbc->disconnect_if_idle;

        system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );
    }
}

done_testing();
