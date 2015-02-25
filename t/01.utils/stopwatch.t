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
