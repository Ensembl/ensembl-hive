package Bio::EnsEMBL::Hive::Limiter;


sub new {
    my ($class, $available_capacity) = @_;

    my $self = bless {}, $class;
    $self->available_capacity( $available_capacity );

        # we fix the multiplier at 1 for direct limiters, but expect it to be (re)set later by reciprocal limiters:
    $self->multiplier( 1 );     

    return $self;
}


sub available_capacity {
    my $self = shift @_;

    if(@_) {
        $self->{_available_capacity} = shift @_;
    }
    return $self->{_available_capacity};
}


sub multiplier {
    my $self = shift @_;

    if(@_) {
        $self->{_multiplier} = shift @_;
    }
    return $self->{_multiplier};
}


sub reached {
    my $self = shift @_;

    return defined($self->available_capacity) && ($self->available_capacity <= 0.0);
}


sub preliminary_offer {
    my ($self, $slots_asked) = @_;

    if( defined($self->available_capacity) and (my $multiplier = $self->multiplier) > 0.0 ) {    # if multiplier is not positive, capacity stays unaffected
        my $slots_available = int($self->available_capacity * $multiplier);

        return ($slots_available<$slots_asked) ? $slots_available : $slots_asked;
    }

    return $slots_asked;
}


sub final_decision {
    my ($self, $slots_agreed) = @_;

    if( defined($self->available_capacity) and (my $multiplier = $self->multiplier) > 0.0 ) {    # if multiplier is not positive, capacity stays unaffected

        $self->available_capacity( $self->available_capacity - $slots_agreed/$multiplier );
    }
}


1;
