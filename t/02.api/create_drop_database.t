#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
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

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_urls make_new_db_from_sqls run_sql_on_db db_cmd);

my $ehive_test_pipeline_urls = get_test_urls();

foreach my $test_url (@$ehive_test_pipeline_urls) {
  subtest 'Test on '.$test_url => sub {

    # -no_sql_schema_version_check is needed because the database does not have the eHive schema
    my $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-url => $test_url);

    # To ensure we start with the database being absent
    system(@{ $dbc->to_cmd(undef, undef, undef, 'DROP DATABASE IF EXISTS') });

    run_sql_on_db($test_url, 'DROP DATABASE IF EXISTS', "Don't complain if asked to drop a database that doesn't exist");
    if ($dbc->driver eq 'sqlite') {
        run_sql_on_db($test_url, 'DROP DATABASE', "'rm -f' doesn't care about missing files");
    } else {
        run_sql_on_db($test_url, 'DROP DATABASE', "Can drop a database that exists", {'expect_failure' => 1});
    }
    run_sql_on_db($test_url, 'CREATE DATABASE', 'Can create a database');
    run_sql_on_db($test_url, 'CREATE DATABASE IF NOT EXISTS', 'Further CREATE DATABASE statements are ignored') unless $dbc->driver eq 'pgsql';
    run_sql_on_db($test_url, 'DROP DATABASE', "Can drop a database that exists");
    if ($dbc->driver eq 'pgsql') {
        # PostgreSQL doesn't understand the IF NOT EXISTS version, so we fallback to a regular CREATE DATABASE
        run_sql_on_db($test_url, 'CREATE DATABASE', 'Can create a database');
    } else {
        run_sql_on_db($test_url, 'CREATE DATABASE IF NOT EXISTS', 'Can create a database');
    }

    run_sql_on_db($test_url, 'DROP DATABASE');
  };
}

done_testing();
