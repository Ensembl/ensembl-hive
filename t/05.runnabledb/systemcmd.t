
use strict;
use warnings;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd' );
}
#########################

standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'echo hello world >&2',
});


##
## do some checks
##


done_testing();
