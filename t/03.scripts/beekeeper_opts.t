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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper get_test_url_or_die run_sql_on_db);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

    # Starting a first set of checks with a "GCPct" pipeline

    init_pipeline('Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LongWorker_conf', $pipeline_url);

    my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

    # Check that -sync runs, puts one entry in the beekeeper table, and finishes with LOOP_LIMIT
    beekeeper($pipeline_url, ['-sync']);
    my $beekeeper_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'beekeeper');
    my $beekeeper_rows = $beekeeper_nta->fetch_all();

    is(scalar(@$beekeeper_rows), 1, 'After -sync, there is exactly 1 entry in the beekeeper table');
    my $beekeeper_row = $$beekeeper_rows[0];
    is($beekeeper_row->{'cause_of_death'}, 'LOOP_LIMIT', 'beekeeper finished with cause_of_death LOOP_LIMIT');

    # Check that -run puts one additional in the beekeeper table, it loops once,
    # and finishes with LOOP_LIMIT
    beekeeper($pipeline_url, ['-run', '-meadow_type' => 'LOCAL', -job_limit => 1]);

    $beekeeper_rows = $beekeeper_nta->fetch_all();
    is(scalar(@$beekeeper_rows), 2, 'After -sync and -run, there are exactly 2 entries in the beekeeper table');
    my $found_beekeeper_dash_run = 0;
    foreach my $run_beekeeper_row (@$beekeeper_rows) {
        if ($run_beekeeper_row->{'options'} =~ /-run/) {
            $found_beekeeper_dash_run = 1;
            is($run_beekeeper_row->{'cause_of_death'}, 'LOOP_LIMIT', 'beekeeper -run finished with cause_of_death LOOP_LIMIT');
        }
    }
    is($found_beekeeper_dash_run, 1, 'A beekeeper with option -run was registered in the beekeeper table');

    # Check that -run -job_id with a non-existant job id fails with TASK_FAILED
    my @bad_job_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $hive_dba->dbc->url, '-run', -job_id => 98765);
    system(@bad_job_cmd);
    ok($?, 'beekeeper -run -job_id 98765 exited with a non-zero return code');
    # Not doing this because we expect the command to *fail*
    #beekeeper($hive_dba->dbc->url, ['-run', -job_id => 98765], 'beekeeper -run -job_id 98765 exited with a non-zero return code');

    $beekeeper_rows = $beekeeper_nta->fetch_all();
    is(scalar(@$beekeeper_rows), 3, 'After -sync, -run, and -run -job_id, there are exactly three entries in the beekeeper table');
    my $found_beekeeper_bad_job = 0;
    foreach my $bad_job_beekeeper_row (@$beekeeper_rows) {
        if ($bad_job_beekeeper_row->{'options'} =~ /-job_id/) {
            $found_beekeeper_bad_job = 1;
            is($bad_job_beekeeper_row->{'cause_of_death'}, 'TASK_FAILED', 'beekeeper -run -job_id 98765 finished with cause_of_death TASK_FAILED');
        }
    }
    is($found_beekeeper_bad_job, 1, 'A beekeeper with option -job_id was registered in the beekeeper table');

    # Check that -loop -analyses_pattern with a non-matching pattern fails with TASK_FAILED
    # Not useing beekeeper() because we expect the command to *fail*
    my @bad_pattern_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl',
        -url => $hive_dba->dbc->url,
        -analyses_pattern => 'this_matches_no_analysis',
        '-loop');
    system(@bad_pattern_cmd);
    ok($?, 'beekeeper -loop -analyses_pattern this_matches_no_analysis exited with a non-zero return code');

    $beekeeper_rows = $beekeeper_nta->fetch_all();
    is(scalar(@$beekeeper_rows), 4, 'After 4 beekeeper commands, there are exactly 4 entries in the beekeeper table');
    my $found_beekeeper_bad_pattern = 0;
    foreach my $bad_pattern_beekeeper_row (@$beekeeper_rows) {
        if ($bad_pattern_beekeeper_row->{'options'} =~ /-analyses_pattern/) {
            $found_beekeeper_bad_pattern = 1;
            is($bad_pattern_beekeeper_row->{'cause_of_death'},
                'TASK_FAILED',
                'beekeeper -loop -analyses_pattern [nonmatching] finished with cause_of_death TASK_FAILED');
        }
    }
    is($found_beekeeper_bad_pattern, 1, 'A beekeeper with option -analyses_pattern was registered in the beekeeper table');

    sleep(10); # give worker a bit of time to seed longrunning jobs

    beekeeper($pipeline_url, ['-run', -analyses_pattern => 'longrunning', -meadow_type => 'LOCAL', -job_limit => 1]);

    sleep(10); # give workers time to start

    my $worker_nta = $hive_dba->get_NakedTableAdaptor('table_name' => 'worker');
    my $live_worker_rows = $worker_nta->fetch_all("worker.status != 'DEAD'");
    is(scalar(@$live_worker_rows), 1, 'one active worker');
    my @live_worker_ids;
    foreach my $row (@$live_worker_rows) {
        push(@live_worker_ids, $row->{'worker_id'});
    }

    foreach my $worker_id (@live_worker_ids) {
        beekeeper($pipeline_url, [-killworker => $worker_id]);
    }

    sleep(10); # give workers a bit of time to die

    my $still_alive_worker_rows = $worker_nta->count_all("status != 'DEAD'");
    is($still_alive_worker_rows, 0, "no workers remain alive");

    $hive_dba->dbc->disconnect_if_idle();
    run_sql_on_db($pipeline_url, 'DROP DATABASE');

done_testing();

