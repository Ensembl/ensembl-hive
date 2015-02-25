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
ok($result, 'found something');
ok(exists($result->{'bar'}), 'we think it is correct');
is($result->{'bar'}, 'foobar');

$result = $collection->find_all_by('foo', undef);
#diag Dumper $result;

#is(@$result, 3, 'sensible');

done_testing();
