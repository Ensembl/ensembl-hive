#!/usr/bin/env perl

# Copyright [2019] EMBL-European Bioinformatics Institute
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

use English qw(-no_match_vars);
use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test
  qw(init_pipeline runWorker beekeeper get_test_url_or_die run_sql_on_db);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} //=
  File::Basename::dirname(File::Basename::dirname(
    File::Basename::dirname( Cwd::realpath($PROGRAM_NAME) )
    ) );

my $pipeline_url = get_test_url_or_die();

init_pipeline(
  'Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LongWorker_conf',
  $pipeline_url );

my $hive_dba =
  Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

# Check that the -big_red_button is recognised. Of course if it is it
# will trigger the shutdown - but all it does at this point is
# Beekeeper blocking itself, which has no effect because it doesn't
# actually try to run anything.
beekeeper( $pipeline_url, [ '-big_red_button' ], "beekeper.pl recognises option '-big_red_button'" );

# This will both spawn a worker to claim a job and register another
# beekeeper with the pipeline. Ideally we would run this one in loop
# mode so that we can confirm blocking works, then again having it run
# in the background so that the test suite can continue would be a bit
# messy and given it is quicker to block *all* beekeepers than just
# the active ones, a single-shot run doesn't make that much of a
# difference.
beekeeper( $pipeline_url, [ '-run' ] );
# Give the worker(s) some time to start
sleep(10);

# Now trigger the shutdown for real
beekeeper( $pipeline_url, [ '-big_red_button' ], 'Pipeline shutdown triggered without errors' );
# Give the worker(s) some time to die
sleep(10);

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
