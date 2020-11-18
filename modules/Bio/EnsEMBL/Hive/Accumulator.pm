=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Accumulator

=head1 DESCRIPTION

    A data container object that defines parameters for accumulated dataflow.
    This object is generated from specially designed datalow URLs.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2020] EMBL-European Bioinformatics Institute

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
            $key_signature=~s/(\w+)/$emitting_job->_param_possibly_overridden($1,$output_id)/eg;

            $self->checkEmptyKeys($key_signature, $accu_address);

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

sub checkEmptyKeys {
  my ( $self, $key_signature, $accu_address ) = @_;
  # we get number of brackets, that are empty for key signature and address
  # and verify that each empty brackets in key_signature is empty in adress
  my @curvedBrackets = $self->findEmptyBrackets($key_signature, '{', '}');
  my @curvedBracketsAddress = $self->findEmptyBrackets($accu_address, '{', '}');
  my %addressBrackets = map { $_ => 1 } @curvedBracketsAddress;

  foreach my $position ( @curvedBrackets ) {
    if (!exists($addressBrackets{$position})) {
        die "Null hash key in accumulator";
    }
  }

  my @squareBrackets = $self->findEmptyBrackets($key_signature, '[', ']');
  my @squareBracketsAddress = $self->findEmptyBrackets($accu_address, '[', ']');
  %addressBrackets = map { $_ => 1 } @squareBracketsAddress;

  foreach my $position ( @squareBrackets ) {
    if (!exists($addressBrackets{$position})) {
        die "Null hash key in accumulator";
    }
  }
}

sub findEmptyBrackets {
    my ( $self, $string, $open, $close ) = @_;

    my @result;
    my $offset = 0;
    my $openIndex = 0;
    my $numberOfBracket = 0;
    my $i = 0;

    # we get first open bracket. If next goes closed bracket -
    # we remember the number of this empty bracket (not position,
    # it can differs due key substitution)
    # than we repeat search with offset considering found bracket
    # an array of empty brackets number we return;
    while ($openIndex != -1) {
      $openIndex = index($string, $open, $offset);
      if ( $openIndex != -1) {
        $numberOfBracket = $numberOfBracket + 1;
        if ($close eq substr($string, $openIndex+1, 1))  {
          @result[$i] = $numberOfBracket;
          $i = $i + 1;
        }
      }
      $offset = $openIndex+1;

    };

    return @result;
}

sub toString {
    my $self = shift @_;

    return 'Accumulator(' . $self->display_name . ')';
}

1;
