=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Accumulator

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object that defines parameters for accumulated dataflow.
    This object is generated from specially designed datalow URLs.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::Accumulator;

use strict;
use Scalar::Util ('weaken');

use Bio::EnsEMBL::Utils::Argument ('rearrange');
use Bio::EnsEMBL::Hive::Utils ('stringify');

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my ($adaptor, $struct_name, $signature_template) = 
         rearrange([qw(adaptor struct_name signature_template) ], @_);

    $self->adaptor($adaptor)                        if(defined($adaptor));
    $self->struct_name($struct_name)                if(defined($struct_name));
    $self->signature_template($signature_template)  if(defined($signature_template));

    return $self;
}


sub adaptor {
    my $self = shift @_;

    if(@_) {
        $self->{'_adaptor'} = shift @_;
        weaken $self->{'_adaptor'};
    }

    return $self->{'_adaptor'};
}


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
        $key_signature=~s/(\w+)/$output_id->{$1}/eg;    # FIXME: could be possibly extended in future to also use $self->param() ?

        push @rows, {
            'sending_job_id'    => $sending_job_id,
            'receiving_job_id'  => $receiving_job_id,
            'struct_name'       => $struct_name,
            'key_signature'     => $key_signature,
            'value'             => stringify( $output_id->{$struct_name} ),
        };
    }

    $self->adaptor->store( \@rows );
}


1;

