=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Utils::Collection - A collection object

=cut

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
                                    ? defined($filter_value) && ( (ref($filter_value) eq 'CODE')
                                                                    ? &$filter_value( $actual_value )
                                                                    : ( $filter_value eq $actual_value )
                                                                )
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
                                    ? defined($filter_value) && ( (ref($filter_value) eq 'CODE')
                                                                    ? &$filter_value( $actual_value )
                                                                    : ( $filter_value eq $actual_value )
                                                                )
                                    : !defined($filter_value)
                               );
        }
        push @filtered_elements, $element;
    }

    return \@filtered_elements;
}


sub _find_all_by_subpattern {    # subpatterns can be combined into full patterns using +-,
    my ($self, $pattern) = @_;

    my $filtered_elements;

    if( $pattern=~/^\d+$/ ) {

        $filtered_elements = $self->find_all_by( 'dbID', $pattern );

    } elsif( $pattern=~/^(\d+)\.\.(\d+)$/ ) {

        $filtered_elements = $self->find_all_by( 'dbID', sub { return $1<=$_[0] && $_[0]<=$2; } );

    } elsif( $pattern=~/^(\d+)\.\.$/ ) {

        $filtered_elements = $self->find_all_by( 'dbID', sub { return $1<=$_[0]; } );

    } elsif( $pattern=~/^\.\.(\d+)$/ ) {

        $filtered_elements = $self->find_all_by( 'dbID', sub { return $_[0]<=$1; } );

    } elsif( $pattern=~/^\w+$/) {

        $filtered_elements = $self->find_all_by( 'name', $pattern );

    } elsif( $pattern=~/^[\w\%]+$/) {

        $pattern=~s/\%/.*/g;
        $filtered_elements = $self->find_all_by( 'name', sub { return $_[0]=~/^${pattern}$/; } );
    }

    return $filtered_elements;
}


sub find_all_by_pattern {
    my ($self, $pattern) = @_;

    if( not defined($pattern) ) {

        return [ $self->list ];

    } else {

        my @syll = split(/([+\-,])/, $pattern);

        my %uniq = map { ("$_" => $_) } @{ $self->_find_all_by_subpattern( shift @syll ) };   # initialize with the first syllable

        while(@syll) {
            my $operation   = shift @syll;
            my $subpattern  = shift @syll;

            foreach my $element (@{ $self->_find_all_by_subpattern( $subpattern ) }) {
                if($operation eq '-') {
                    delete $uniq{ "$element" };
                } elsif ($operation eq '+' or $operation eq ',') {
                    $uniq{ "$element" } = $element;
                } else {
                    throw( "Complex pattern '$pattern' not recognized" );
                }
            }
        }

        return [ values %uniq ];
    }
}


sub DESTROY {
    my $self = shift @_;

    $self->listref( [] );
}

1;
