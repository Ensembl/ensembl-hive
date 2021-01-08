#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

$collection = Bio::EnsEMBL::Hive::Utils::Collection->new( [
    { 'dbID' => 2, 'name' => 'beta' },
    { 'dbID' => 1, 'name' => 'alpha' },
    { 'dbID' => 7, 'name' => 'eta' },
    { 'dbID' => 3, 'name' => 'gamma' },
    { 'dbID' => 4, 'name' => 'delta' },
    { 'dbID' => 5, 'name' => 'epsilon' },
    { 'dbID' => 6, 'name' => 'zeta' },
] );

my $odd_elements = $collection->find_all_by( 'dbID', sub { return $_[0] % 2; } );
is(@$odd_elements, 4, '4 odd elements');

my $mix = $collection->find_all_by_pattern( '%-%ta' );
is(@$mix, 3, 'another 3 elements');

done_testing();
