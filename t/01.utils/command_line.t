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
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'parse_cmdline_options' );
}
#########################

## block 1 - simple single and double -- options
{
    ## note we do not require the double minus version
    local @ARGV = qw{-foo bar --alpha beta -count 3};
    my ($pairs, $list) = parse_cmdline_options();
    ok($pairs, 'command line parsed to a hash');
    isa_ok($pairs, 'HASH'); ## really a hash
    ok($list, 'list returned');
    isa_ok($list, 'ARRAY'); ## really a list ref
    is(@$list, 0, 'empty list');
    is($pairs->{'foo'}, 'bar', 'foo option set');
    is($pairs->{'alpha'}, 'beta', 'alpha option set');
    is($pairs->{'count'}, 3, 'count option set');
}

## what happens with one too many - ?
{
    local @ARGV = qw{---wrong option};
    my ($pairs, $list) = parse_cmdline_options();
    is(scalar(keys %$pairs), 0, 'ignore the --- option and assign to list instead');
    is(@$list, 2, 'list is populated');
    is($list->[0], '---wrong', 'no pruning of -');
    is($list->[1], 'option', 'fidelity');
}

## mix of options and extra
{
    local @ARGV = qw{-foo bar alpha beta --lorem ipsum};
    my ($pairs, $list) = parse_cmdline_options();
    ok($pairs, 'good');
    ok($list, 'still good');
    is($pairs->{'foo'}, 'bar', 'option foo set to bar');
    is($list->[0], 'alpha', 'centuri');
    is($list->[1], 'beta', 'globulin');
    is($pairs->{'lorem'}, 'ipsum', 'still latin');
}

## complex option array
{
    local @ARGV = (q!--foo=["bar","foobar"]!, 'alpha');
    my ($pairs, $list) = parse_cmdline_options();
    ok($pairs, 'pairs');
    isa_ok($pairs->{'foo'}, 'ARRAY'); ## array value
    is(@$list, 1, 'still set');

}

## complex option hash
{
    local @ARGV = (q!--foo={"bar" => "foobar"}!, 'alpha');
    my ($pairs, $list) = parse_cmdline_options();
    ok($pairs, 'pairs');
    isa_ok($pairs->{'foo'}, 'HASH'); ## hash value
    is(@$list, 1, 'still set');
}

## trailing key
{
    local @ARGV = qw{-foo bar alpha -beta};
    my ($pairs, $list) = parse_cmdline_options();
    ok($pairs, 'pairs');
    ok($list, 'list');
    is(@$list, 1, 'alpha only');
    is($list->[0], 'alpha', 'no beta here');
    is($pairs->{'foo'}, 'bar', 'bar still');
}

done_testing();
