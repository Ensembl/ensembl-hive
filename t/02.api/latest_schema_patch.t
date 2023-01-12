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

use Cwd;
use File::Basename;
use File::Temp qw/tempfile/;

use Test::More;

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_urls run_sql_on_db make_new_db_from_sqls);


BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Version' );
    use_ok( 'Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor' );
}
#########################

$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $current_version = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version();
my $prev_version = $current_version - 1;
my $ref_commit = "sql_schema_${current_version}_start^1";

# A temporary file to store the old schema
my ($fh, $filename) = tempfile(UNLINK => 1);
close($fh);

sub schema_from_url {
    my $url = shift;
    my $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-url => $url);
    if ($dbc->driver eq 'mysql') {
        # For some reasons, column_info(undef, undef, '%', '%') doesn't
        # work on MySQL ... We need to call it on each table explicitly
        my $sth = $dbc->table_info(undef, undef, '%');
        my @table_names = keys %{ $sth->fetchall_hashref('TABLE_NAME') };
        my %schema;
        foreach my $t (@table_names) {
            $sth = $dbc->column_info(undef, undef, $t, '%');
            $schema{$t} = $sth->fetchall_hashref('ORDINAL_POSITION');
        }
        return \%schema;
    } elsif ($dbc->driver eq 'pgsql') {
        my $sth = $dbc->column_info(undef, undef, '%', '%');
        my $schema = $sth->fetchall_hashref(['TABLE_NAME', 'COLUMN_NAME']);
        foreach my $s (values %$schema) {
            # PostgreSQL language does not have a way of forcing the position
            # of a column. This means that patches that add columns cannot
            # produce the same new schema, so we can't use the ORDINAL position
            # when comparing the schemas
            delete $_->{'ORDINAL_POSITION'} for values %$s;
            # Since version 3.8.0 DBD::Pg returns the database name in
            # TABLE_CAT. Since we are comparing different databases (i.e.
            # travis_ehive_test_old_patched vs travis_ehive_test_new), we
            # can't use TABLE_CAT in the comparison
            delete $_->{'TABLE_CAT'} for values %$s;
        }
        $sth->finish();
        return $schema;
    } else {
        my $sth = $dbc->column_info(undef, undef, '%', '%');
        my $schema = $sth->fetchall_hashref(['TABLE_NAME', 'ORDINAL_POSITION']);
        $sth->finish();
        return $schema;
    }
}

my %schema_files = (
    'mysql' => ['sql/tables.mysql', 'sql/procedures.mysql', 'sql/foreign_keys.sql'],
    'pgsql' => ['sql/tables.pgsql', 'sql/procedures.pgsql', 'sql/foreign_keys.sql'],
    'sqlite' => ['sql/tables.sqlite', 'sql/procedures.sqlite'],
);

my $n_drivers_with_patch = 0;
foreach my $driver (qw(mysql pgsql sqlite)) {

    my $patches_to_apply = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_sql_schema_patches($prev_version, $driver);
    next unless ($patches_to_apply && scalar(@$patches_to_apply));
    $n_drivers_with_patch++;

    subtest "$driver patch" => sub {
        is(scalar(@$patches_to_apply), 1, 'No more than 1 patch');

        my $url1 = get_test_urls(-driver => $driver, -tag => 'old_patched')->[0] or return;
        my $gitshow_command = sprintf('cd %s; git show %s > %s', $ENV{'EHIVE_ROOT_DIR'}, join(' ', map {$ref_commit.':'.$_} @{$schema_files{$driver}}), $filename);
        ok(!system($gitshow_command), "Extracted the schema as it was in version $prev_version");
        make_new_db_from_sqls($url1, [$filename, $patches_to_apply->[0]], 'Can create a database from the previous schema and patch it');

        my $url2 = get_test_urls(-driver => $driver, -tag => 'new')->[0];
        ok($url2, 'Test database available2') or return;
        my @new_files = map {$ENV{'EHIVE_ROOT_DIR'}.'/'.$_} @{$schema_files{$driver}};
        make_new_db_from_sqls($url2, \@new_files, 'Can create a database from the current schema');

        my $schema1 = schema_from_url($url1);
        my $schema2 = schema_from_url($url2);
        is_deeply($schema1, $schema2, 'Both schemas are identical');

        # For debugging
        #note($url1);
        #note($url2);
        run_sql_on_db($url1, 'DROP DATABASE');
        run_sql_on_db($url2, 'DROP DATABASE');
    };
}

ok($n_drivers_with_patch, 'At least 1 driver has a patch');

done_testing();
