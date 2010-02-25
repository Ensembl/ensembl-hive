=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::ResourceDescription

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object (the only methods are getters/setters) that corresponds to a row in 'resource_description' table:

    CREATE TABLE resource_description (
        rc_id                 int(10) unsigned DEFAULT 0 NOT NULL,
        meadow_type           enum('LSF', 'LOCAL') DEFAULT 'LSF' NOT NULL,
        parameters            varchar(255) DEFAULT '' NOT NULL,
        description           varchar(255) DEFAULT NULL,
        PRIMARY KEY(rc_id, meadow_type)
    ) ENGINE=InnoDB;

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::ResourceDescription;

use strict;
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my ($adaptor, $rc_id, $meadow_type, $parameters ,$description) =
         rearrange([qw(adaptor rc_id meadow_type parameters description) ], @_);

    $self->adaptor($adaptor) if(defined($adaptor));
    $self->rc_id($rc_id);
    $self->meadow_type($meadow_type);
    $self->parameters($parameters);
    $self->description($description);

    return $self;
}

sub adaptor {
    my $self = shift @_;

    if(@_) {
        $self->{'_adaptor'} = shift @_;
    }
    return $self->{'_adaptor'};
}

sub rc_id {
    my $self = shift @_;

    if(@_) {
        $self->{'_rc_id'} = shift @_;
    }
    return $self->{'_rc_id'};
}

sub meadow_type {
    my $self = shift @_;

    if(@_) {
        $self->{'_meadow_type'} = shift @_;
    }
    return $self->{'_meadow_type'};
}

sub parameters {
    my $self = shift @_;

    if(@_) {
        $self->{'_parameters'} = shift @_;
    }
    return $self->{'_parameters'};
}

sub description {
    my $self = shift @_;

    if(@_) {
        $self->{'_description'} = shift @_;
    }
    return $self->{'_description'};
}

sub to_string {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(rc_id meadow_type parameters description) ));
}

1;

