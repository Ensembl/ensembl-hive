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
    my ($self, $method, $filter_value) = @_;

    my @values = grep { $_->$method() eq $filter_value } $self->list;

    return $values[0];
}


sub find_all_by {
    my ($self, $method, $filter_value) = @_;

    my @values = grep { $_->$method() eq $filter_value } $self->list;

    return \@values;
}


sub DESTROY {
    my $self = shift @_;

    $self->listref( [] );
}

1;
