#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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
use Time::HiRes qw(time);

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

my $min_overhead;

for (1..10) {
    my $t = time();
    standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::Dummy', {
        'take_time' => 0,
    });
    my $d = time() - $t;
    $min_overhead = $d if (not defined $min_overhead) || ($d < $min_overhead);
}

my $wait = 10;
my $t = time();
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::Dummy', {
    'take_time' => $wait,
});
my $d = time() - $t;
# We allow the runnable to be 5 times faster than the fastest attempt so far
cmp_ok($d, '>=', $wait+$min_overhead/5, 'The "take_time" parameter made the runnable sleep a bit');

done_testing();
