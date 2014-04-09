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


sub add {
    my $self = shift @_;

    push @{ $self->listref }, @_;
}


sub find_one_by {
    my ($self, %method_to_filter_value) = @_;

    ELEMENT: foreach my $element (@{ $self->listref }) {
        keys %method_to_filter_value;   # sic! This is to "rewind" the each% operator to the beginning each time
        while(my ($filter_name, $filter_value) = each %method_to_filter_value) {
            my $actual_value = (ref($element) eq 'HASH') ? $element->{$filter_name} : $element->$filter_name();
            next ELEMENT unless( defined($actual_value)   # either both defined and equal or neither defined
                                    ? defined($filter_value) && ($actual_value eq $filter_value)
                                    : !defined($filter_value)
                               );
        }
        return $element;
    }
}


sub find_all_by {
    my ($self, %method_to_filter_value) = @_;

    my @filtered_elements = ();

    ELEMENT: foreach my $element (@{ $self->listref }) {
        keys %method_to_filter_value;   # sic! This is to "rewind" the each% operator to the beginning each time
        while(my ($filter_name, $filter_value) = each %method_to_filter_value) {
            my $actual_value = (ref($element) eq 'HASH') ? $element->{$filter_name} : $element->$filter_name();
            next ELEMENT unless( defined($actual_value)   # either both defined and equal or neither defined
                                    ? defined($filter_value) && ($actual_value eq $filter_value)
                                    : !defined($filter_value)
                               );
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
