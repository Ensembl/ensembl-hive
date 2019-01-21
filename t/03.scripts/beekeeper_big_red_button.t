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

# Check that the -big_red_button is recognised
beekeeper( $pipeline_url, ['-big_red_button'] );

$hive_dba->dbc->disconnect_if_idle();
run_sql_on_db( $pipeline_url, 'DROP DATABASE' );

done_testing();


1;
