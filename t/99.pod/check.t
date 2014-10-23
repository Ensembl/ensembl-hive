
use strict;
use warnings;
use Test::More;
use lib 't/lib';
use Hive::Config;
use File::Spec::Functions qw{catdir};

diag "Testing for Plain Old Documentation (POD) validity...";

eval "use Test::Pod 1.00";

plan skip_all => "Test::Pod 1.00 required for testing POD" if $@;

## use this as filtering of source might occur
my @pod_dirs = map { catdir $ENV{EHIVE_ROOT_DIR}, 'blib', $_ } qw{lib script};

# diag "all pod files in @pod_dirs";

all_pod_files_ok( all_pod_files( @pod_dirs ) );
