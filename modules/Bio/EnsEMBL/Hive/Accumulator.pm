=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Accumulator

=head1 DESCRIPTION

    A data container object that defines parameters for accumulated dataflow.
    This object is generated from specially designed datalow URLs.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Accumulator;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify');

use base ( 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'accu_name', 'accu_address', 'accu_input_variable' ];
}


sub accu_name {
    my $self = shift @_;

    if(@_) {
        $self->{'_accu_name'} = shift @_;
    }
    return $self->{'_accu_name'};
}


sub accu_address {
    my $self = shift @_;

    if(@_) {
        $self->{'_accu_address'} = shift @_;
    }
    return ( $self->{'_accu_address'} // '' );
}


sub accu_input_variable {
    my $self = shift @_;

    if(@_) {
        $self->{'_accu_input_variable'} = shift @_;
    }
    return ( $self->{'_accu_input_variable'} // $self->accu_name );
}


sub url_query_params {
     my ($self) = @_;

     return {   # direct access to the actual (possibly missing) values
        'accu_name'             => $self->accu_name,
        'accu_address'          => $self->{'_accu_address'},
        'accu_input_variable'   => $self->{'_accu_input_variable'},
     };
}


sub display_name {
    my ($self) = @_;
    return  $self->accu_name
            . $self->accu_address
            . ':='
            . $self->accu_input_variable;
}


sub dataflow {
    my ( $self, $output_ids, $emitting_job ) = @_;

    if(my $receiving_semaphore = $emitting_job->controlled_semaphore) {

        my $sending_job_id          = $emitting_job->dbID;
        my $receiving_semaphore_id  = $receiving_semaphore->dbID;
        my $accu_adaptor            = $receiving_semaphore->adaptor->db->get_AccumulatorAdaptor;

        my $accu_name           = $self->accu_name;
        my $accu_address        = $self->accu_address;
        my $accu_input_variable = $self->accu_input_variable;

        my @rows = ();

        foreach my $output_id (@$output_ids) {

            my $key_signature = $accu_address;
            $key_signature=~s{(\w+)}{$emitting_job->_param_possibly_overridden($1,$output_id) // '' }eg;

            _check_empty_keys($key_signature, $accu_address);

            push @rows, {
                'sending_job_id'            => $sending_job_id,
                'receiving_semaphore_id'    => $receiving_semaphore_id,
                'struct_name'               => $accu_name,
                'key_signature'             => $key_signature,
                'value'                     => stringify( $emitting_job->_param_possibly_overridden($accu_input_variable, $output_id) ),
            };
        }

        $accu_adaptor->store( \@rows );

    } else {
        die "No controlled semaphore, cannot perform accumulated dataflow";
    }
}

=head2 _check_empty_keys

    Description: a private function that checks the $key_signature for empty
    bracket pairs that weren't empty before

=cut

sub _check_empty_keys {
    my ( $key_signature, $accu_address ) = @_;

    foreach my $pair ( ( ['{', '}'], ['[', ']'] ) ) {

        # verify that each empty pair of brackets in key_signature was also empty in accu_address
        my $empty_in_key = _find_empty_brackets( $key_signature, $pair->[0], $pair->[1] );
        my $empty_in_address = _find_empty_brackets( $accu_address, $pair->[0], $pair->[1] );
        my %empty_in_address_idx = map { $_ => 1 } @$empty_in_address;

        foreach my $index (@$empty_in_key) {
            if ( !exists( $empty_in_address_idx{$index} ) ) {
                die "A key in the accumulator had an empty substitution. Bracket '"
                  . $pair->[0] . $pair->[1] .
                  "' pair number $index, substitution from '$accu_address' to '$key_signature'";
            }
        }
    }
}

=head2 _find_empty_brackets

    Description: a private function that finds and counts opening brackets in a
    string
    Returns: a ref to an array with an entry for each empty bracket pair. The
    entry is the count of how many preceding opening brackets there are.

=cut

sub _find_empty_brackets {
    my ( $string, $open, $close ) = @_;
    my $count  = 0;
    my $result = [];

    # look for opening bracket
    while ( $string =~ /\Q$open/g ) {
        # count how many opening brackets we have
        $count++;
        if ( $string =~ /\G(?=$close)/ ) {
            # store number of bracket if we find an empty pair (like {})
            push( @$result, $count );
        }
    }
    return $result;
}

sub toString {
    my $self = shift @_;

    return 'Accumulator(' . $self->display_name . ')';
}

1;
