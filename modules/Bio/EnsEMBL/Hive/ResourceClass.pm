=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::ResourceClass

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object (the only methods are getters/setters) that corresponds to a row in 'resource_class' table:

    CREATE TABLE resource_class (
        resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,     # unique internal id
        name                varchar(40) NOT NULL,

        PRIMARY KEY(resource_class_id)
    ) ENGINE=InnoDB;

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::ResourceClass;

use strict;

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );
 

sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

    my ($name) =
         rearrange([qw(name) ], @_);

    $self->name($name) if($name);

    return $self;
}


sub name {
    my $self = shift @_;

    if(@_) {
        $self->{'_name'} = shift @_;
    }
    return $self->{'_name'};
}


sub toString {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(dbID name) ));
}

1;

