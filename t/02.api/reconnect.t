#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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

use Cwd;
use File::Basename;

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;

use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_url_or_die run_sql_on_db make_new_db_from_sqls);
use Bio::EnsEMBL::Hive::Utils::URL;

# For finding the sample db dump's location, so it can be loaded.
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );


sub kill_active_connection {
    my ($dbname, $server_url) = @_;
    my $find_pid_sql = "SELECT ID FROM information_schema.processlist " .
      "WHERE DB = '$dbname'";
    my $find_pid_cmd = $ENV{'EHIVE_ROOT_DIR'}.'/scripts/db_cmd.pl ' .
      "-url $server_url " .
	"-sql \"$find_pid_sql\" | grep -v ID";

    my @find_pid_results = `$find_pid_cmd`;
    chomp @find_pid_results;

    if (scalar(@find_pid_results) > 1) {
      BAIL_OUT("more than one process id accessing test database (pids: ".join(', ', @find_pid_results)."), bailing out");
    }

    my ($found_pid) = @find_pid_results;

    my $kill_sql = "KILL $found_pid";
    run_sql_on_db($server_url, $kill_sql);
}


SKIP: {
    my $db_url = eval { get_test_url_or_die(-driver => 'mysql') };
    skip "no MySQL test database defined", 1 unless $db_url;
    my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse($db_url);
    
    my $dbname;
    if ($parsed_url->{dbname} ne '') {
      $dbname = $parsed_url->{dbname};
    } else {
      BAIL_OUT("db url $db_url did not have a parsable dbname - check that get_test_urls.t also fails");
    }
    
    # Build a database-less URL so that we can identify the ID of the connection to the database
    delete $parsed_url->{dbname};
    my $server_url = Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($parsed_url);
    
    my $dbc = make_new_db_from_sqls( $db_url, [ $ENV{'EHIVE_ROOT_DIR'} . '/t/02.api/sql/reconnect_test.sql' ], 'Create database with many rows');
    
    my $dbc_query_sql = "SELECT SQL_NO_CACHE * FROM manyrows";
    
    my $sth = $dbc->prepare($dbc_query_sql);
    ok(!$sth->{Active}, 'Statement handle not yet active');
    $sth->execute();
    ok($sth->{Active}, 'Statement handle now active');

    is_deeply($sth->{NAME}, ['id', 'avalue'], 'Got the correct column names');

    kill_active_connection($dbname, $server_url);
    
    my $fetched_row_count = 0;
    while (my @values = $sth->fetchrow_array()) {
      $fetched_row_count++;
    }
    ok(!$sth->{Active}, 'Statement handle not active any more');
    is($fetched_row_count, 10, "were we able to fetch all rows after a db kill");

    ## Let's now test some dbh methods called by BaseAdaptor

    # -no_sql_schema_version_check is needed because the database does not have the eHive schema
    my $hive_dba        = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-dbconn => $dbc, -no_sql_schema_version_check => 1);
    my $manyrows_nta    = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'manyrows' );
    # open a connection and fetch the table schema
    my $column_set_1    = $manyrows_nta->column_set;

    kill_active_connection($dbname, $server_url);

    # clear the cached value to force fetching it again from the database
    delete $manyrows_nta->{_column_set};
    my $column_set_2    = $manyrows_nta->column_set;
    is_deeply($column_set_2, $column_set_1, 'column_set can be fetched, despite the connection having been killed');
}

done_testing();

