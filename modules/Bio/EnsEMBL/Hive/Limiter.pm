package Bio::EnsEMBL::Hive::Limiter;


sub new {
    my ($class, $description, $available_capacity) = @_;

    my $self = bless {}, $class;
    $self->description( $description );
    $self->available_capacity( $available_capacity );

        # we fix the multiplier at 1 for direct limiters, but expect it to be (re)set later by reciprocal limiters:
    $self->multiplier( 1 );     

    return $self;
}


sub description {
    my $self = shift @_;

    if(@_) {
        $self->{_description} = shift @_;
    }
    return $self->{_description};
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

    my $available_capacity  = $self->available_capacity;
    my $multiplier          = $self->multiplier;

    if( defined($available_capacity) and defined($multiplier) and ($multiplier >= 0.0) ) {  # if multiplier is negative it is not limiting
        my $slots_available = int($available_capacity * $multiplier);

        return ($slots_available<$slots_asked) ? $slots_available : $slots_asked;
    }

    return $slots_asked;
}


sub final_decision {
    my ($self, $slots_agreed) = @_;

    my $available_capacity  = $self->available_capacity;
    my $multiplier          = $self->multiplier;

    if( defined($available_capacity) and defined($multiplier) and ($multiplier > 0.0) ) {   # if multiplier is not positive capacity stays unaffected
                                                                                            # and we should not arrive here if $multiplier==0

        $self->available_capacity( $available_capacity - $slots_agreed/$multiplier );
    }
}


1;
