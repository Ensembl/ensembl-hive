=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::ResourceDescription

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object (the only methods are getters/setters) that corresponds to a row in 'resource_description' table:

    CREATE TABLE resource_description (
        resource_class_id     int(10) unsigned NOT NULL,
        meadow_type           varchar(40) NOT NULL,
        submission_cmd_args     VARCHAR(255) NOT NULL DEFAULT '',
        worker_cmd_args         VARCHAR(255) NOT NULL DEFAULT '',

        PRIMARY KEY(resource_class_id, meadow_type)
    ) ENGINE=InnoDB;

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::ResourceDescription;

use strict;
use Scalar::Util ('weaken');

use Bio::EnsEMBL::Utils::Argument ('rearrange');

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my ($adaptor, $resource_class_id, $meadow_type, $submission_cmd_args, $worker_cmd_args) =
         rearrange([qw(adaptor resource_class_id meadow_type submission_cmd_args worker_cmd_args) ], @_);

    $self->adaptor($adaptor) if(defined($adaptor));
    $self->resource_class_id($resource_class_id);
    $self->meadow_type($meadow_type);
    $self->submission_cmd_args($submission_cmd_args);
    $self->worker_cmd_args($worker_cmd_args);

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


sub resource_class_id {
    my $self = shift @_;

    if(@_) {
        $self->{'_resource_class_id'} = shift @_;
    }
    return $self->{'_resource_class_id'};
}


sub meadow_type {
    my $self = shift @_;

    if(@_) {
        $self->{'_meadow_type'} = shift @_;
    }
    return $self->{'_meadow_type'};
}


sub submission_cmd_args {
    my $self = shift @_;

    if(@_) {
        $self->{'_submission_cmd_args'} = shift @_;
    }
    return $self->{'_submission_cmd_args'} || '';
}


sub worker_cmd_args {
    my $self = shift @_;

    if(@_) {
        $self->{'_worker_cmd_args'} = shift @_;
    }
    return $self->{'_worker_cmd_args'} || '';
}


sub toString {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(resource_class_id meadow_type submission_cmd_args worker_cmd_args) ));
}

1;

