#!/usr/bin/env perl

# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Collection' );
}
#########################

my $collection = Bio::EnsEMBL::Hive::Utils::Collection->new(['the']);
ok($collection, 'and creates objects');

my $ref = $collection->listref;
is(@$ref, 1, 'correct size');

my @ref = $collection->list;
is(@ref, 1, 'still correct size');

my $i = 1;
foreach my $member(qw{quick brown fox}) { 
    $collection->add($member);
    is(@$ref, ++$i, 'addition - same object');
    is(@ref, 1, 'no addition as it was a copy');
}

ok($collection->present('fox'), 'present() - There is a fox');
ok(!$collection->present('chickens'), '!present() - The fox is unlucky');

$collection->add_once('fox');
is(@$ref, $i, 'Same size - there can be only 1 fox');
$collection->add_once('human');
is(@$ref, ++$i, 'Addition - Someone comes in');

$collection->forget('fox');
is(@$ref, --$i, 'one less element - the fox is gone: we\'re safe !');

$collection = Bio::EnsEMBL::Hive::Utils::Collection->new([{ foo => undef}]);
$collection->add({ foo => undef });
$collection->add({ bar => 'foobar' });
$collection->add({ foo => undef });

my $listref = $collection->listref;
is(@$listref, 4, '4 elements');

my $result = $collection->find_one_by(bar => 'foobar');
ok($result, 'found something');
ok(exists($result->{'bar'}), 'we think it is correct');
is($result->{'bar'}, 'foobar');

$result = $collection->find_all_by('foo', undef);
#diag Dumper $result;

#is(@$result, 3, 'sensible');

$collection = Bio::EnsEMBL::Hive::Utils::Collection->new( [
    { 'dbID' => 2, 'name' => 'beta',    'colour' => 'red',      'size' => 10 },
    { 'dbID' => 1, 'name' => 'alpha',   'colour' => 'orange',   'size' =>  5 },
    { 'dbID' => 7, 'name' => 'eta',     'colour' => 'yellow',   'size' =>  2 },
    { 'dbID' => 3, 'name' => 'gamma',   'colour' => 'green',    'size' =>  1 },
    { 'dbID' => 4, 'name' => 'delta',   'colour' => 'yellow',   'size' => 20 },
    { 'dbID' => 5, 'name' => 'epsilon', 'colour' => 'orange',   'size' => 25 },
    { 'dbID' => 6, 'name' => 'zeta',    'colour' => 'red',      'size' =>  0 },
] );

my $odd_elements = $collection->find_all_by( 'dbID', sub { return $_[0] % 2; } );
is(@$odd_elements, 4, '4 odd elements');

my $mix = $collection->find_all_by_pattern( '%-%ta' );
is(@$mix, 3, 'another 3 elements');

$mix = $collection->find_all_by_pattern( '3' );
is(@$mix, 1, 'find_all_by_pattern - single dbID');

$mix = $collection->find_all_by_pattern( '3..5' );
is(@$mix, 3, 'find_all_by_pattern - dbID range');

$mix = $collection->find_all_by_pattern( '4..' );
is(@$mix, 4, 'find_all_by_pattern - open range (right)');

$mix = $collection->find_all_by_pattern( '..3' );
is(@$mix, 3, 'find_all_by_pattern - open range (left)');

$mix = $collection->find_all_by_pattern( 'gamma' );
is(@$mix, 1, 'find_all_by_pattern - single name (no %)');

$mix = $collection->find_all_by_pattern( 'gamma+5' );
is(@$mix, 2, 'find_all_by_pattern - combined patterns (no overlap)');

$mix = $collection->find_all_by_pattern( 'gamma+3' );
is(@$mix, 1, 'find_all_by_pattern - combined patterns (overlap)');

$mix = $collection->find_all_by_pattern( 'colour==yellow' );
is(@$mix, 2, 'find_all_by_pattern - selecting by a fields equality');

$mix = $collection->find_all_by_pattern( 'size<10,colour==orange' );
is(@$mix, 5, 'find_all_by_pattern - selecting by a fields inequality');

done_testing();
