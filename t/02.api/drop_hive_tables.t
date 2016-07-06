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

use Test::More tests => 4;
use Test::Exception;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_urls);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url;

  my $available_test_urls = get_test_urls(-driver => 'mysql');
  if (scalar(@$available_test_urls) > 0) {
    $pipeline_url = $$available_test_urls[0];
  } else {
    $pipeline_url = "NONE";
  }

SKIP: {
  skip "no MySQL test database defined", 4 if ($pipeline_url eq "NONE");
  
  my $url             = init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf', [-pipeline_url => $pipeline_url, -hive_force_init => 1]);
  
  my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
						       -url                        => $url,
						       -disconnect_when_inactive   => 1,
						      );
  
  my $dbc = $pipeline->hive_dba->dbc;
  
  lives_ok( sub {
	      $dbc->do('CALL drop_hive_tables;');
	    }, 'CALL drop_hive_tables does not fail');
  
  my $table_list = $dbc->db_handle->selectcol_arrayref('SHOW TABLE STATUS', { Columns => [1] });
  
  is_deeply( $table_list, ['final_result'], 'All the eHive tables have been removed by "drop_hive_tables"'); 
  
  system(@{ $dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') });
  
}

done_testing();

