#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
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

use Test::More tests => 3;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_url_or_die make_hive_db);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

SKIP: {
  my $pipeline_url = eval { get_test_url_or_die(-driver => 'mysql') };
  skip "no MySQL test database defined", 3 unless $pipeline_url;
  
  my $dbc = make_hive_db($pipeline_url, 'force_init');

  lives_ok( sub {
	      $dbc->do('CALL drop_hive_tables;');
	    }, 'CALL drop_hive_tables does not fail');
  
  my $table_list = $dbc->db_handle->selectcol_arrayref('SHOW TABLE STATUS', { Columns => [1] });
  
  is_deeply( $table_list, [], 'All the eHive tables have been removed by "drop_hive_tables"');
  
  $dbc->disconnect_if_idle();
  system(@{ $dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') });
  
}

done_testing();

