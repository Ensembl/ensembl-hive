#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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
use Test::More tests => 20;
use Test::Exception;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Params' );
}


my $ini_params = {
    'alpha' => 2,
    'beta' => 5,
    'beta_prime' => '#beta#',

    'delta' => '#expr( #alpha#*#beta# )expr#',

    # there is a syntax error on purpose, but Perl doesn't mind. It just warns:
    # Scalar found where operator expected at (eval 23) line 1, near ") $self" (Missing operator before $self?)
    'error_bad_delta' => '#expr( #alpha# #beta# )expr#',

    'gamma' => [10,20,33,15],
    'gamma_prime' => '#gamma#',
    'gamma_expr' => '#expr( [ @{#gamma#} ] )expr#',

    'age' => { 'Alice' => 17, 'Bob' => 20, 'Chloe' => 21},
    'age_prime' => '#age#',
    'age_expr' => '#expr( { %{#age#} } )expr#',

    'csv' => '123,456,789',
    'csv_prime' => '#csv#',
    'listref' => '#expr([eval #csv#])expr#',

    'undefined' => undef,
    'undefined_prime' => '#undefined#',

    'empty_string' => '',
    'empty_string_prime' => '#empty_string#',

    'zero'  => 0,
    'zero_prime' => '#zero#',

    'missing' => '#thisdoesnotexist#',
    'missing_prime' => '#missing#',
    'missing_expr' => '#expr(#missing#)expr#',
    'missing_expr_add' => '#expr(3+#missing#)expr#',

    'error_expr_add' => '#expr(3/#zero#)expr#',
};

my $params = Bio::EnsEMBL::Hive::Params->new();
$params->param_init({%$ini_params});

is_deeply($params->{_unsubstituted_param_hash}, $ini_params, "the initialisation keeps the hash content");

subtest 'Params::param_exists()', sub {
    plan tests => (1+scalar(keys %$ini_params));
    foreach my $k (keys %$ini_params) {
        if ($k =~ /error/) {
            throws_ok {$params->param_exists($k)} qr/ParamError: Cannot evaluate the expression/, "Syntax errors throw exceptions";
        } elsif ($k =~ /missing/) {
            throws_ok {$params->param_exists($k)} qr/ParamError: the evaluation of '(.*)' requires '(.*)' which is missing/, "Missing parameters throw exceptions";
        } else {
            is($params->param_exists($k), 1, "The parameter '$k' exists");
        }
    }
    is($params->param_exists('there_is_no_parameter_with_this_name'), 0, "Absent parameters don't exist");
};

subtest 'Params::param_is_defined()', sub {
    plan tests => (1+scalar(keys %$ini_params));
    foreach my $k (keys %$ini_params) {
        if ($k =~ /error/) {
            throws_ok {$params->param_is_defined($k)} qr/ParamError: Cannot evaluate the expression/, "Syntax errors throw exceptions";
        } elsif ($k =~ /missing/) {
            throws_ok {$params->param_is_defined($k)} qr/ParamError: the evaluation of '(.*)' requires '(.*)' which is missing/, "Missing parameters throw exceptions";
        } elsif ($k =~ /undefined/) {
            is($params->param_is_defined($k), 0, "The parameter '$k' is not defined");
        } else {
            is($params->param_is_defined($k), 1, "The parameter '$k' is defined");
        }
    }
    is($params->param_is_defined('there_is_no_parameter_with_this_name'), 0, "Absent parameters are not defined");
};

subtest 'Params::param_required()', sub {
    plan tests => (1+scalar(keys %$ini_params));
    foreach my $k (keys %$ini_params) {
        if ($k =~ /error/) {
            throws_ok {$params->param_required($k)} qr/ParamError: Cannot evaluate the expression/, "Syntax errors throw exceptions";
        } elsif ($k =~ /missing/) {
            throws_ok {$params->param_required($k)} qr/ParamError: the evaluation of '(.*)' requires '(.*)' which is missing/, "Missing parameters throw exceptions";
        } elsif ($k =~ /undefined/) {
            throws_ok {$params->param_required($k)} qr/ParamError: value for param_required(.*) is required and has to be defined/, "The parameter '$k' is not defined and cannot be required";
        } else {
            ok(defined $params->param_required($k), "The parameter '$k' can be required");
        }
    }
    is($params->param_is_defined('there_is_no_parameter_with_this_name'), 0, "Absent parameters are not defined");
};

subtest 'Params::param()', sub {
    plan tests => (1+scalar(keys %$ini_params));
    foreach my $k (keys %$ini_params) {
        if ($k =~ /error/) {
            throws_ok {$params->param($k)} qr/ParamError: Cannot evaluate the expression/, "Syntax errors throw exceptions";
        } elsif ($k =~ /missing/) {
            throws_ok {$params->param($k)} qr/ParamError: the evaluation of '(.*)' requires '(.*)' which is missing/, "Missing parameters throw exceptions";
        } elsif ($k =~ /undefined/) {
            is($params->param($k), undef, "The parameter '$k' is not defined");
        } else {
            ok(defined $params->param($k), "The parameter '$k' can be required");
        }
    }
    is($params->param_is_defined('there_is_no_parameter_with_this_name'), 0, "Absent parameters are not defined");
};

subtest 'Getters for basic types (no substitutions)', sub {
    plan tests => 7;
    is($params->param('alpha'), $ini_params->{alpha}, 'Number (non-0)');
    is($params->param('zero'), $ini_params->{zero}, 'Number (0)');
    is($params->param('csv'), $ini_params->{csv}, 'String (non-empty)');
    is($params->param('empty_string'), $ini_params->{empty_string}, 'String (empty)');
    is_deeply($params->param('age'), $ini_params->{age}, 'Hash-ref');
    is_deeply($params->param('gamma'), $ini_params->{gamma}, 'Array-ref');
    is($params->param('undefined'), $ini_params->{undefined}, 'undef');
};

subtest 'Getters for basic types (via aliases)', sub {
    plan tests => 7;
    is($params->param('beta_prime'), $ini_params->{beta}, 'Number (non-0)');
    is($params->param('zero_prime'), $ini_params->{zero}, 'Number (0)');
    is($params->param('csv_prime'), $ini_params->{csv}, 'String (non-empty)');
    is($params->param('empty_string_prime'), $ini_params->{empty_string}, 'String (empty)');
    is_deeply($params->param('age_prime'), $ini_params->{age}, 'Hash-ref');
    is_deeply($params->param('gamma_prime'), $ini_params->{gamma}, 'Array-ref');
    is($params->param('undefined_prime'), $ini_params->{undefined}, 'undef');
};

subtest 'Expressions with de-referencing', sub {
    plan tests => 2;
    is_deeply($params->param('age_expr'), $ini_params->{age}, 'Hash-ref');
    is_deeply($params->param('gamma_expr'), $ini_params->{gamma}, 'Aarray-ref)');
};

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
