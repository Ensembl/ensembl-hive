
use strict;
use warnings;

use lib 't/lib/';
use Test::More;
use Data::Dumper;

BEGIN {
    ## at least it compiles
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Stopwatch' );
}
#########################

my $total_stopwatch    = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart;
my $sleepfor_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart;
ok($sleepfor_stopwatch, 'and creates objects');
ok($total_stopwatch, 'and creates objects');

sleep(1);

$sleepfor_stopwatch->pause();
my $slept = $sleepfor_stopwatch->get_elapsed;

do_some_work();

is($slept, $sleepfor_stopwatch->get_elapsed, 'pausing pauses');

isnt($sleepfor_stopwatch->get_elapsed, $total_stopwatch->get_elapsed, 'different');

sub do_some_work {
    for(my $i = 0; $i < 1e6; ++$i){
	$i++ unless $i % 1e5;
    }
}

done_testing();
