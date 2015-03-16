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
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'stringify', 'destringify' );
}
#########################


my $structure = {
    'foo' => 'bar',
    'bar' => 'foobar'
};

my $struct_string = stringify $structure;
ok($struct_string, 'returned a value');
is($struct_string, q!{"bar" => "foobar","foo" => "bar"}!, 'correct representation');


$struct_string = stringify $structure;
ok($struct_string, 'returned a value');
is($struct_string, q!{"bar" => "foobar","foo" => "bar"}!, 'correct representation');

$structure = {
    foo => 'bar',
    latin => {
	lorem => {
	    ipsum => 'dolor',
	},
	atrium => 'foo bar',
    }
};

$Data::Dumper::Maxdepth = 1;
$struct_string = stringify $structure;
ok($structure, 'value returned');
is($struct_string, 
   q!{"foo" => "bar","latin" => {"atrium" => "foo bar","lorem" => {"ipsum" => "dolor"}}}!,
   'correct depth');

my $destructure = destringify $struct_string;
ok($destructure, 'recreated a hash');
isa_ok($destructure, 'HASH'); ## really is a hash
is($destructure->{'foo'}, 'bar', 'foo value correct');
is($destructure->{'latin'}{'lorem'}{'ipsum'}, 'dolor', 'latin test');

$destructure = destringify "[{ 'alpha' => 'beta' }, { 'gamma' => 'delta'}, {'omega' => undef}]";
isa_ok($destructure, 'ARRAY'); ## got an array
is($destructure->[0]{'alpha'}, 'beta', 'hash entry');
is($destructure->[2]{'omega'}, undef, 'undef values');

done_testing();
