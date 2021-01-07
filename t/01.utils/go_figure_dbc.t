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

done_testing();
