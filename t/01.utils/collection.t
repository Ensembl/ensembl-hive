#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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
use Test::Exception;


BEGIN {
    ## at least it compiles
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Collection' );
    use_ok( 'Bio::EnsEMBL::Hive::ResourceDescription' );
}

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

$collection->forget_and_mark_for_deletion('fox');
is(@$ref, --$i, 'one less element - the fox is gone: we\'re safe !');

# Make sure it's gone !
# Also, we test forget when the dark-collection has already been created
$collection->forget_and_mark_for_deletion('fox');
is(@$ref, $i, 'No foxes around');

ok($collection->dark_collection->present('fox'));

$collection = Bio::EnsEMBL::Hive::Utils::Collection->new([{ foo => undef}]);
$collection->add({ foo => undef });
$collection->add({ bar => 'foobar' });
$collection->add({ foo => undef });

my $listref = $collection->listref;
is(@$listref, 4, '4 elements');

my $result = $collection->find_one_by(bar => 'foobar');
ok(exists($result->{'bar'}), 'got a result');
is($result->{'bar'}, 'foobar', 'we think it is correct');

## The following test's result may look unexpected due to implicit autovivification,
## so I have switched it off -- lg4
#$result = $collection->find_all_by('foo', undef);
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

my $missing_element = $collection->find_one_by( 'dbID' => 10 );
is($missing_element, undef, 'Missing element is returned as undef');

my $missing_elements = $collection->find_all_by( 'colour' => 'impossible' );
is_deeply($missing_elements, [ ], 'Missing elements are returned as an empty list');

$result = $collection->find_all_by('foo', undef);
#diag Dumper $result;

#is(@$result, 3, 'sensible');

my $data_list = [
    { 'dbID' => 2, 'name' => 'beta',    'colour' => 'red',        'size' => 10 },
    { 'dbID' => 1, 'name' => 'alpha',   'colour' => 'orange',     'size' =>  5 },
    { 'dbID' => 7, 'name' => 'eta',     'colour' => 'yellow',     'size' =>  2 },
    { 'dbID' => 3, 'name' => 'gamma',   'colour' => 'green',      'size' =>  1 },
    { 'dbID' => 4, 'name' => 'delta',   'colour' => 'yellow,red', 'size' => 20 },
    { 'dbID' => 5, 'name' => 'epsilon', 'colour' => 'orange',     'size' => 25 },
    { 'dbID' => 6, 'name' => 'zeta',    'colour' => 'redish',     'size' =>  0 },
];

$collection = Bio::EnsEMBL::Hive::Utils::Collection->new( $data_list );

my $odd_elements = $collection->find_all_by( 'dbID', sub { return $_[0] % 2; } );
is(@$odd_elements, 4, '4 odd elements');

my $all = $collection->find_all_by_pattern();
is_deeply($all, $data_list, 'find_all_by_pattern() with no arguments returns the whole list');

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

$mix = $collection->find_all_by_pattern( '%eta' );
is(@$mix, 3, 'find_all_by_pattern - regex name (with %)');

$mix = $collection->find_all_by_pattern( 'gamma+5' );
is(@$mix, 2, 'find_all_by_pattern - combined patterns (no overlap)');

$mix = $collection->find_all_by_pattern( 'gamma+3' );
is(@$mix, 1, 'find_all_by_pattern - combined patterns (overlap)');

$mix = $collection->find_all_by_pattern( 'colour==orange' );
is(@$mix, 2, 'find_all_by_pattern - selecting by a fields equality');

$mix = $collection->find_all_by_pattern( 'colour~red%' );
is(@$mix, 3, 'find_all_by_pattern - selecting by a fields regex');

$mix = $collection->find_all_by_pattern( 'size!=20' );
is(@$mix, 6, 'find_all_by_pattern - difference');

$mix = $collection->find_all_by_pattern( 'dbID>=5' );
is(@$mix, 3, 'find_all_by_pattern - greater or equal');

$mix = $collection->find_all_by_pattern( 'dbID<=4' );
is(@$mix, 4, 'find_all_by_pattern - lower or equal');

$mix = $collection->find_all_by_pattern( 'size>10' );
is(@$mix, 2, 'find_all_by_pattern - greater than');

$mix = $collection->find_all_by_pattern( 'size<5' );
is(@$mix, 3, 'find_all_by_pattern - greater than');

$mix = $collection->find_all_by_pattern( 'size<10,colour==orange' );
is(@$mix, 5, 'find_all_by_pattern - selecting by a fields inequality');

throws_ok {$collection->find_all_by_pattern( 'size!' )} qr/The pattern '.*' is not recognized/, "Using an invalid pattern throws an exception";

# Try a collection with objects
my $dummy_resource = Bio::EnsEMBL::Hive::ResourceDescription->new( 'meadow_type' => 'LOCAL', 'submission_cmd_args' => '-q long', 'worker_cmd_args' => '' );
$collection = Bio::EnsEMBL::Hive::Utils::Collection->new( [ $dummy_resource ] );

$result = $collection->find_one_by( 'meadow_type' => 'LOCAL' );
is( $result, $dummy_resource, 'Collection search on an object attribute (match)');

$mix = $collection->find_all_by_pattern( 'meadow_type==LOCAL' );
is_deeply( $mix, [$dummy_resource], 'Collection filtering on an object attribute (match)');

$mix = $collection->find_all_by_pattern( 'meadow_type==LSF' );
is_deeply( $mix, [], 'Collection filtering on an object attribute (no match)');

done_testing();
