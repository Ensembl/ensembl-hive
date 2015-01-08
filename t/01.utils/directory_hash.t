
use strict;
use warnings;

use Test::More;
use Data::Dumper;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'dir_revhash' );
}
#########################

my $directory_structure = dir_revhash 123456789;
ok( $directory_structure, 'simply returns a string' );
is( $directory_structure, '9/8/7/6/5/4/3/2', 'string is expected');

done_testing();
