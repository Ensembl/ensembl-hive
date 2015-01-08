
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
is(@sorted_configs, 13, 'lucky number');
my ($generic) = grep { /HiveGeneric_conf/ } @sorted_configs;
ok($generic, 'found generic base config');

## loading the module

my $module = load_file_or_module( $generic );
is( $module, $generic, 'all good' );

## and by file name ...


done_testing();
