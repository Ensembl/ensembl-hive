#!/usr/bin/env perl
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


=pod

=head1 DESCRIPTION

    A script for testing parameter substitution in Bio::EnsEMBL::Hive::Params class.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


use strict;
use warnings;

use Bio::EnsEMBL::Hive::Params;
use Bio::EnsEMBL::Hive::Utils ('stringify');

my $params = Bio::EnsEMBL::Hive::Params->new();

$params->param_init({
    'alpha' => 2,
    'beta' => 5,
    'delta' => '#expr( #alpha#*#beta# )expr#',

    'gamma' => [10,20,33,15],
    'gamma_prime' => '#expr( [ @{#gamma#} ] )expr#',

    'age' => { 'Alice' => 17, 'Bob' => 20, 'Chloe' => 21},
    'age_prime' => '#expr( { %{#age#} } )expr#',

    'csv' => '123,456,789',
    'listref' => '#expr([eval #csv#])expr#',
});

print $params->param_substitute( "Substituting one scalar: #alpha# and another: #beta# and again one: #alpha# and the other: #beta# . Their product: #delta#\n" );

print $params->param_substitute( "This is csvq:gamma -> #csvq:gamma#\n" );
print $params->param_substitute( "\tsum(gamma) -> #expr( sum (\@{#gamma#}) )expr#\n" );
print $params->param_substitute( "\tcsvq(gamma) -> #expr( csvq(undef,#gamma#) )expr#\n" );  # note the first argument ($self) has to be substituted by a dummy undef
print $params->param_substitute( "\tjoin(sort(gamma)) -> #expr( join(', ', sort \@{#gamma#}))expr#\n" );
print $params->param_substitute( "\tthe expression behind csvq reproduced using expr()expr -> #expr( join(', ', map {\"'\$ _'\"} sort \@{#gamma#}))expr#\n\n" );

print $params->param_substitute( 'adding indexed values: #expr( #age#->{Alice}+(max @{#gamma#}) )expr#' )."\n";

print $params->param_substitute( 'joined gamma: #expr( join(", ", @{ #gamma# } ) )expr#'."\n" );
print $params->param_substitute( 'joined gamma_prime: #expr( join(", ", @{#gamma_prime#}) )expr#'."\n" );

print $params->param_substitute( 'complex fold of age: #expr( join("\t", map { $ _.":".#age#->{$ _}} keys %{#age#}) )expr#' )."\n";
print $params->param_substitute( 'complex fold of age_prime: #expr( join("\t", map { $ _.":".#age_prime#->{$ _}} keys %{#age_prime#}) )expr#' )."\n";

print "\ncsv = '".$params->param('csv')."'\n";
my $listref = $params->param_substitute( '#listref#' );
print "list reference produced by evaluating csv: ".stringify($listref)."\n";

