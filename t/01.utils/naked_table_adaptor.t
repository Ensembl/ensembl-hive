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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );



my $pipeline_url      = 'sqlite:///ehive_test_pipeline_db';

my $url         = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf', [-pipeline_url => $pipeline_url, -hive_force_init => 1]);

my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
    -url                        => $url,
    -disconnect_when_inactive   => 1,
);

my $hive_dba            = $pipeline->hive_dba;

my $final_result_nta    = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
my $analysis_nta        = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'analysis_base' );
my $final_result2_nta   = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );

is($final_result_nta, $final_result2_nta, "Adaptors with identical creation parameters are cached as expected");
isnt($final_result_nta, $analysis_nta, "Adaptors with different creation parameters are cached separately as expected");

my $first_hash  = { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788', 'result' => '3159063427494563172' };
my $second_hash = { 'b_multiplier' => '9650156169', 'a_multiplier' => '327358788', 'result' => '3159063427494563172' };

$final_result_nta->store( $first_hash );
$final_result_nta->store( $second_hash );

my $final_results = $final_result_nta->fetch_all();
is_deeply( $final_results, [ $first_hash, $second_hash ], "The data stored into final_result table is as expected");


system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );

done_testing();
