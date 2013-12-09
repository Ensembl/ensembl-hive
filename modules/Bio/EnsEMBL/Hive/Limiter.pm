=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Limiter;

=head1 DESCRIPTION

    A simple data object that has a conditional capper/minimizer built in.
    Simple but very useful in the context of multi-parameter scheduling.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


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
