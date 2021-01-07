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

use List::Util qw(first min max minstr maxstr reduce sum shuffle);              # make them available for substituted expressions
use Test::More tests => 19;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Params' );
}


my $ini_params = {
    'alpha' => 2,
    'beta' => 5,
    'delta' => '#expr( #alpha#*#beta# )expr#',

    'gamma' => [10,20,33,15],
    'gamma_prime' => '#expr( [ @{#gamma#} ] )expr#',

    'age' => { 'Alice' => 17, 'Bob' => 20, 'Chloe' => 21},
    'age_prime' => '#expr( { %{#age#} } )expr#',

    'csv' => '123,456,789',
    'listref' => '#expr([eval #csv#])expr#',
};

my $params = Bio::EnsEMBL::Hive::Params->new();
$params->param_init(1, $ini_params);

is_deeply($params->{_unsubstituted_param_hash}, $ini_params, "the initialisation keeps the hash content");

is($params->param('alpha'), $ini_params->{alpha}, 'Straightforward parameter definition (number)');
is($params->param('csv'), $ini_params->{csv}, 'Straightforward parameter definition (string)');
is_deeply($params->param('age'), $ini_params->{age}, 'Straightforward parameter definition (hash-ref)');
is_deeply($params->param('gamma'), $ini_params->{gamma}, 'Straightforward parameter definition (array-ref)');

is_deeply($params->param('age_prime'), $ini_params->{age}, 'Alias definition (hash-ref)');
is_deeply($params->param('gamma_prime'), $ini_params->{gamma}, 'Alias definition (array-ref)');

is($params->param_substitute("substituted #alpha# there"), "substituted ".$ini_params->{alpha}." there", "basic param substitution");
is($params->param('delta'), $ini_params->{alpha} * $ini_params->{beta}, '#expr()expr# can compute a product');

is($params->param_substitute("#csvq:gamma#"), join(',', map {"'$_'"} @{$ini_params->{gamma}}), '#cvsq:# can join an array-ref');
is($params->param_substitute("#expr( csvq(undef,#gamma#) )expr#"), join(',', map {"'$_'"} @{$ini_params->{gamma}}), 'Another way of calling cvsq');
is($params->param_substitute("#expr( join(', ', map {\"'\$ _'\"} sort \@{#gamma#}))expr#"), join(', ', map {"'$_'"} sort @{$ini_params->{gamma}}), 'Yet another way of calling cvsq');

is($params->param_substitute("#expr( sum (\@{#gamma#}) )expr#"), sum(@{$ini_params->{gamma}}), '#expr()expr# can compute the sum of an array-ref');

is($params->param_substitute("#expr( join(', ', sort \@{#gamma#}))expr#"), join(', ', sort @{$ini_params->{gamma}}), 'combo with join() and sort()');

is($params->param_substitute('#expr( #age#->{Alice}+(max @{#gamma#}) )expr#'), $ini_params->{age}->{Alice}+max(@{$ini_params->{gamma}}), 'adding indexed values');

is_deeply($params->param('listref'), [split(/,/, $ini_params->{csv})], 'list reference produced by evaluating csv');

is(
    $params->param_substitute('#expr( join("\t", sort map { $ _.":".#age#->{$ _}} keys %{#age#}) )expr#'),
    "Alice:17\tBob:20\tChloe:21",
    'complex fold of age'
);

is(
    $params->param_substitute('#expr( join("\t", reverse sort map { $ _.":".#age_prime#->{$ _}} keys %{#age_prime#}) )expr#'),
    "Chloe:21\tBob:20\tAlice:17",
    'complex fold of age_prime'
);

done_testing();
