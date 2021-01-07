#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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
use File::Temp qw{tempdir};
use Data::Dumper;

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

my $dir = tempdir CLEANUP => 1;
my $orig = Cwd::getcwd;
chdir $dir;

my $sqlite_url = "sqlite:///test_db";
# -no_sql_schema_version_check is needed because the database does not have the eHive schema
my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $sqlite_url, -no_sql_schema_version_check => 1);
my $dbc = $hive_dba->dbc();

system( $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl', '-url', $sqlite_url, '-sql', 'CREATE DATABASE' );
$dbc->do('CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'),

my $final_result_nta    = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
my $analysis_nta        = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'analysis_base' );
my $final_result2_nta   = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );

is($final_result_nta, $final_result2_nta, "Adaptors with identical creation parameters are cached as expected");
isnt($final_result_nta, $analysis_nta, "Adaptors with different creation parameters are cached separately as expected");

# Unfortunately this isn't set by the constructor
$final_result_nta->table_name('final_result');
$analysis_nta->table_name('analysis_base');

my $first_hash  = { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788', 'result' => '3159063427494563172' };
my $second_hash = { 'b_multiplier' => '9650156169', 'a_multiplier' => '327358788', 'result' => '3159063427494563172' };

$final_result_nta->store( $first_hash );
$final_result_nta->store( $second_hash );

my $final_results = $final_result_nta->fetch_all();
is_deeply( $final_results, [ $first_hash, $second_hash ], "The data stored into final_result table is as expected");

my $third_hash = { 'a_multiplier' => $first_hash->{a_multiplier}, 'b_multiplier' => '1', 'result' => $first_hash->{a_multiplier} };
$final_result_nta->store( $third_hash );

is($final_result_nta->count_all_by_a_multiplier($first_hash->{a_multiplier}), 2, '2 result for this a_multiplier');

system( $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl', '-url', $sqlite_url, '-sql', 'DROP DATABASE' );
chdir $orig;

done_testing();
