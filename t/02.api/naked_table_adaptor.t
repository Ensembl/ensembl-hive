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


use strict;
use warnings;

use Test::More;
use Data::Dumper;

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_urls make_new_db_from_sqls run_sql_on_db);

my $ehive_test_pipeline_urls = get_test_urls();

foreach my $test_url (@$ehive_test_pipeline_urls) {
subtest 'Test on '.$test_url => sub {

my $sql_create_table = [
    'CREATE TABLE final_result (a_multiplier varchar(40) NOT NULL, b_multiplier varchar(40) NOT NULL, result varchar(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))',
    'CREATE TABLE analysis_base (name char(40) NOT NULL)',
];
my $dbc = make_new_db_from_sqls($test_url, $sql_create_table, 'Database with a few tables');

# -no_sql_schema_version_check is needed because the database does not have the eHive schema
my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-dbconn => $dbc, -no_sql_schema_version_check => 1);

my $final_result_nta    = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
my $analysis_nta        = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'analysis_base' );
my $final_result2_nta   = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
my $final_result3_nta   = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result', 'insertion_method' => 'INSERT_IGNORE' );
my $final_result4_nta   = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result', 'insertion_method' => 'REPLACE' );

is($final_result_nta, $final_result2_nta, "Adaptors with identical creation parameters are cached as expected");
isnt($final_result_nta, $analysis_nta, "Adaptors with different creation parameters are cached separately as expected");

my $first_hash  = { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788', 'result' => '3159063427494563172' };
my $second_hash = { 'b_multiplier' => '9650156169', 'a_multiplier' => '327358788', 'result' => '3159063427494563172' };

$final_result_nta->store( $first_hash );
$final_result_nta->store( $second_hash );

my $final_results = [sort {$a->{'b_multiplier'} <=> $b->{'b_multiplier'}} @{ $final_result_nta->fetch_all() }];
is_deeply( $final_results, [ $first_hash, $second_hash ], "The data stored into final_result table is as expected");

my $third_hash = { 'a_multiplier' => $first_hash->{a_multiplier}, 'b_multiplier' => '1', 'result' => $first_hash->{a_multiplier} };
$final_result_nta->store( $third_hash );

is_deeply($final_result_nta->count_all_HASHED_FROM_a_multiplier(), {$first_hash->{a_multiplier} => 2, $second_hash->{a_multiplier} => 1}, '3 results in total in the table, 2 of which share the same a_multiplier');
is($final_result_nta->count_all_by_a_multiplier($first_hash->{a_multiplier}), 2, '2 result for this a_multiplier');
is_deeply($final_result_nta->count_all_by_a_multiplier_HASHED_FROM_b_multiplier($first_hash->{a_multiplier}), {$first_hash->{b_multiplier} => 1, $third_hash->{b_multiplier} => 1}, '2 different b_multiplier for this a_multiplier');

if($dbc->driver ne 'pgsql') {
    my $first_hash_plus_one = { 'a_multiplier' => $first_hash->{'a_multiplier'}, 'b_multiplier' => $first_hash->{'b_multiplier'}, 'result' => $first_hash->{'result'}+1 };

    $final_result3_nta->store( $first_hash_plus_one );
    my $insert_ignore_result = $final_result3_nta->fetch_by_a_multiplier_AND_b_multiplier( $first_hash_plus_one->{'a_multiplier'}, $first_hash_plus_one->{'b_multiplier'});
    is_deeply($insert_ignore_result, $first_hash, "Ignored a row with a key collision correctly");

    $final_result4_nta->store( $first_hash_plus_one );
    my $last_result = $final_result3_nta->fetch_by_a_multiplier_AND_b_multiplier( $first_hash_plus_one->{'a_multiplier'}, $first_hash_plus_one->{'b_multiplier'});
    is_deeply($last_result, $first_hash_plus_one, "Replaced the value correctly");
}

$dbc->disconnect_if_idle;
run_sql_on_db($test_url, 'DROP DATABASE');

};
}


done_testing();
