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

use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Test::More;

BEGIN {
    ## at least it compiles
    use_ok( 'Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail' );
}

subtest 'format_table' => sub {
    my $title = 'Table title';
    my $columns = ['a', 'b'];
    my $data = [ ['x', 'y'], ['', '0'], [undef, '12345678'] ];
    my $expected_table = <<'END';
Table title
+-----+----------+
| a   | b        |
+-----+----------+
| x   | y        |
|     | 0        |
| N/A | 12345678 |
+-----+----------+
END
    my $got_table = Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail->format_table($title, $columns, $data);
    is($got_table, $expected_table, 'Table with empty strings and missing values');
};


done_testing();
