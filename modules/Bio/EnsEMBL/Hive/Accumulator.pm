=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Accumulator

=head1 DESCRIPTION

    A data container object that defines parameters for accumulated dataflow.
    This object is generated from specially designed datalow URLs.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Utils ('stringify');

use base ( 'Bio::EnsEMBL::Hive::Storable' );


sub struct_name {
    my $self = shift @_;

    if(@_) {
        $self->{'_struct_name'} = shift @_;
    }
    return $self->{'_struct_name'};
}


sub signature_template {
    my $self = shift @_;

    if(@_) {
        $self->{'_signature_template'} = shift @_;
    }
    return $self->{'_signature_template'};
}


sub url {
    my $self    = shift @_;
    my $ref_dba = shift @_;     # if reference dba is the same as 'our' dba, a shorter url can be generated

    if(my $adaptor = $self->adaptor) {
        my $dbc_prefix = ($adaptor->db == $ref_dba) ? ':///' : $adaptor->db->dbc->url();
        return $dbc_prefix .'/accu?'.$self->struct_name(). '=' . $self->signature_template();
    } else {
        return;
    }
}


sub dataflow {
    my ( $self, $output_ids, $emitting_job ) = @_;

    my $sending_job_id      = $emitting_job->dbID();
    my $receiving_job_id    = $emitting_job->semaphored_job_id() || die "No semaphored job, cannot perform accumulated dataflow";

    my $struct_name         = $self->struct_name();
    my $signature_template  = $self->signature_template();

    my @rows = ();

    foreach my $output_id (@$output_ids) {

        my $key_signature = $signature_template;
        $key_signature=~s/(\w+)/$emitting_job->_param_possibly_overridden($1,$output_id)/eg;

        push @rows, {
            'sending_job_id'    => $sending_job_id,
            'receiving_job_id'  => $receiving_job_id,
            'struct_name'       => $struct_name,
            'key_signature'     => $key_signature,
            'value'             => stringify( $emitting_job->_param_possibly_overridden($struct_name, $output_id) ),
        };
    }

    $self->adaptor->store( \@rows );
}

1;

