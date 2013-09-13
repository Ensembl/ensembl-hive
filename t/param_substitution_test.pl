#!/usr/bin/env perl

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Params;

my $params = Bio::EnsEMBL::Hive::Params->new();

$params->param_init(1, { 'alpha' => 2, 'beta' => 5, 'gamma' => [10,20,33,15], 'delta' => '#expr( #alpha#*#beta# )expr#', 'age' => { 'Alice' => 17, 'Bob' => 20, 'Chloe' => 21} });

print $params->param_substitute( "Substituting one scalar: #alpha# and another: #beta# and again one: #alpha# and the other: #beta# . Their product: #delta#\n" );

print $params->param_substitute( 'Old syntax needs single quotes or escaping the dollar. #expr( "One scalar: $alpha and another: $beta and again one: $alpha and another: $beta" )expr#' )."\n";

print $params->param_substitute( "This is csvq:gamma -> #csvq:gamma# and this is an expr()expr -> #expr( join(', #alpha#, ', sort \@{#gamma#}))expr#\n" );
print $params->param_substitute( 'adding indexed values: #expr( #age#->{Alice}+(max @{#gamma#}) )expr#' )."\n";
print $params->param_substitute( 'complex fold: #expr( join(", ", map { $ _.":".#age#->{$ _}} keys %{#age#}) )expr#' )."\n";

