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
use Scalar::Util ('weaken');

use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'
 

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my ($adaptor, $dbID, $name) =
         rearrange([qw(adaptor dbID name) ], @_);

    $self->adaptor($adaptor) if(defined($adaptor));
    $self->dbID($dbID);
    $self->name($name);

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


sub dbID {
    my $self = shift @_;

    if(@_) {
        $self->{'_resource_class_id'} = shift @_;
    }
    return $self->{'_resource_class_id'};
}


sub name {
    my $self = shift @_;

    if(@_) {
        $self->{'_name'} = shift @_;
    }
    return $self->{'_name'};
}


sub to_string {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(dbID name) ));
}

1;

