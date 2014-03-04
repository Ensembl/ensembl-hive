package Bio::EnsEMBL::Hive::Utils::Collection;

use strict;
use warnings;


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    $self->listref( shift @_ || [] );

    return $self;
}


sub listref {
    my $self = shift @_;

    if(@_) {
        $self->{'_listref'} = shift @_;
    }
    return $self->{'_listref'};
}


sub list {
    my $self = shift @_;

    return @{ $self->listref };
}


sub hashed_by_dbID {
    my $self = shift @_;

    return { map { $_->dbID => $_ } $self->list };
}


sub find_one_by {
    my ($self, %method_to_filter_value) = @_;

    ELEMENT: foreach my $element (@{ $self->listref }) {
        keys %method_to_filter_value;   # sic! This is to "rewind" the each% operator to the beginning each time
        while(my ($method, $filter_value) = each %method_to_filter_value) {
            next ELEMENT unless($element->$method() eq $filter_value);
        }
        return $element;
    }
}


sub find_all_by {
    my ($self, %method_to_filter_value) = @_;

    my @filtered_elements = ();

    ELEMENT: foreach my $element (@{ $self->listref }) {
        keys %method_to_filter_value;   # sic! This is to "rewind" the each% operator to the beginning each time
        while(my ($method, $filter_value) = each %method_to_filter_value) {
            next ELEMENT unless($element->$method() eq $filter_value);
        }
        push @filtered_elements, $element;
    }

    return \@filtered_elements;
}


sub DESTROY {
    my $self = shift @_;

    $self->listref( [] );
}

1;
