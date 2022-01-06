#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

use Test::More;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor' );
}
#########################

$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

# This test assumes that the MySQL schema can and is always patched
my $from_version = 60;
my $patches_to_apply = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_sql_schema_patches($from_version, 'mysql');
ok($patches_to_apply, 'the adaptor found some patches to apply');
is(scalar(@$patches_to_apply), Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version() - $from_version, 'correct number of patches');

done_testing();
