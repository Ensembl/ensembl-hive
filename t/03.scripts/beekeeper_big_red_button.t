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

package BeekeeperBigRedButtonTests;

use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test
    qw( init_pipeline runWorker beekeeper get_test_url_or_die run_sql_on_db );


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} //=
  File::Basename::dirname( File::Basename::dirname(
      File::Basename::dirname( Cwd::realpath($PROGRAM_NAME) )
  ) );
my $local_module_path = $ENV{'EHIVE_ROOT_DIR'}.'/t/03.scripts/';

# The JSON config file to set CleanupTempDirectoryKilledWorkers to 1
my $json_config = $PROGRAM_NAME;
$json_config =~ s/\.t$/.json/;

# The name of the file that will be created in the temp directory
my $test_filename = 'foo';

my $pipeline_url = get_test_url_or_die();

{
    # The init_pipeline test runs in the same process, so @INC needs
    # to be updated to see the test modules
    local @INC = @INC;
    push @INC, $local_module_path;
    init_pipeline(
        'TestPipeConfig::LongWorker_conf',
        $pipeline_url,
        [],
        [
            'analysis[longrunning].module=TestRunnable::DummyWriter',
            "analysis[longrunning].parameters={'filename' => '$test_filename'}",
        ],
    );
}

my $hive_dba =
    Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

my $big_red_button_options = [ '-big_red_button', '-config_file', $json_config ];
# Check that the -big_red_button is recognised. Of course if it is it
# will trigger the shutdown - but all it does at this point is
# Beekeeper blocking itself, which has no effect because it doesn't
# actually try to run anything.
beekeeper( $pipeline_url, $big_red_button_options, "beekeper.pl recognises option '-big_red_button'" );

# This will both spawn a worker to claim a job and register another
# beekeeper with the pipeline. Ideally we would run this one in loop
# mode so that we can confirm blocking works, then again having it run
# in the background so that the test suite can continue would be a bit
# messy and given it is quicker to block *all* beekeepers than just
# the active ones, a single-shot run doesn't make that much of a
# difference.
{
    # The beekeeper test runs in a separate process, so PERL5LIB needs
    # to be updated in order to see TestRunnable::DummyWriter
    local $ENV{'PERL5LIB'} = "$local_module_path:" . $ENV{'PERL5LIB'};
    beekeeper( $pipeline_url, [ '-run' ] );
}
# Give the worker(s) some time to start
sleep(10);

# The file should have been created
my $worker = $hive_dba->get_WorkerAdaptor->fetch_by_dbID(1);
my $temp_directory_name = $worker->temp_directory_name;
my $hello_path = "$temp_directory_name/$test_filename";
ok(-s $hello_path, "$hello_path file has been populated");

# Now trigger the shutdown for real
beekeeper( $pipeline_url, $big_red_button_options, 'Pipeline shutdown triggered without errors' );
# Give the worker(s) some time to die
sleep(10);

# The directory should have been removed
ok(!(-e $temp_directory_name), "$temp_directory_name has been removed");

my $bk_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'beekeeper' );
my $unblocked_beekeeper_rows = $bk_nta->fetch_all( 'cause_of_death IS NULL AND is_blocked != 1' );
is( scalar @{ $unblocked_beekeeper_rows }, 0, 'All non-dead beekeepers have been blocked' );

my $w_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'worker' );
my $alive_worker_rows = $w_nta->fetch_all( "status != 'DEAD'" );
is( scalar @{ $alive_worker_rows }, 0, 'No non-dead workers remaining' );

$hive_dba->dbc->disconnect_if_idle();
run_sql_on_db( $pipeline_url, 'DROP DATABASE' );

done_testing();


1;
