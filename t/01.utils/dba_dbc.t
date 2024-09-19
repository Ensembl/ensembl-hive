#!/usr/bin/env perl

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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
use Test::Exception;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils qw(go_figure_dbc);
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

my $pipeline_url = 'mysql://user@' . 'localhost:3306/ehive_test_pipeline_db';

# conversion of generic DBConnection to Bio::EnsEMBL::Hive::DBSQL::DBConnection
my $fake_dbc = {};
bless $fake_dbc, 'Fake::DBConnection';
my $real_dbc = go_figure_dbc($fake_dbc);
isa_ok($real_dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection');

# passing a url returns a valid hive dbc
my $url_dbc = go_figure_dbc($pipeline_url);
isa_ok($url_dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection');
is($url_dbc->url(), $pipeline_url, "dbc created from url returns the same url");

# passing a hash returns a valid hive dbc
my $hash_dbc = go_figure_dbc({-driver => 'mysql',
			      -dbname => 'ehive_test_pipeline_db',
			      -host => 'localhost',
			      -user => 'user'});
isa_ok($hash_dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection');
is($hash_dbc->url(), $pipeline_url, "dbc created from hash generates appropriate url");

# passing something that has a dbc method returns a dbc
my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-url => $pipeline_url,
						   -no_sql_schema_version_check => 1);
my $dba2dbc = go_figure_dbc($dba);
isa_ok($dba2dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection');
like($dba->species, qr/^Bio::EnsEMBL::Hive::DBSQL::DBAdaptor=HASH\(0x[[:xdigit:]]+\)$/, 'The DBAdaptor has a unique "species" name');

SKIP: {
    eval { require Bio::EnsEMBL::Registry; };

    skip "The Ensembl Core API is not installed" if $@;

    my $registry_species_name = 'dummy_species';

    my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
        -url => $pipeline_url,
        -species => $registry_species_name,
        -no_sql_schema_version_check => 1,
    );

    is($dba->species, $registry_species_name, 'The DBAdaptor has the correct "species" name');

    my $dba_from_registry = Bio::EnsEMBL::Registry->get_DBAdaptor($registry_species_name, 'hive');
    is($dba_from_registry, $dba, 'The DBAdaptor is registered in the Ensembl Registry');

    throws_ok {
        Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(-reg_conf => '/non_existent_file');
    } qr/Configuration file .* does not exist. Registry configuration not loaded/, 'Throws a relevant message if the path doesn\'t exist';

}

done_testing();
