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

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'load_file_or_module', 'find_submodules' );
}
#########################

my $hive = find_submodules 'Bio::EnsEMBL::Hive';
isa_ok($hive, 'ARRAY');
cmp_ok(scalar(@$hive), '>', 0, 'modules loaded');

my $pipe_configs = find_submodules 'Bio::EnsEMBL::Hive::PipeConfig';
ok($pipe_configs, 'configs found');
isa_ok($pipe_configs, 'ARRAY'); ## still an array
my @sorted_configs = sort { $a cmp $b } @$pipe_configs;
my ($generic) = grep { /HiveGeneric_conf/ } @sorted_configs;
ok($generic, 'found generic base config');

## loading the module

my $module = load_file_or_module( $generic );
is( $module, $generic, 'all good' );

## and by file name ...


done_testing();
