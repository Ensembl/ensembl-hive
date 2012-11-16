# A base class for objects that we want to be configurable in the following sense:
#   1) have a pointer to the $config
#   2) know their context
#   3) automatically apply that context when getting and setting

package Bio::EnsEMBL::Hive::Configurable;

use strict;
use warnings;


sub config {
    my $self = shift @_;

    if(@_) {
        $self->{'_config'} = shift @_;
    }
    return $self->{'_config'};
}


sub context {
    my $self = shift @_;

    if(@_) {
        $self->{'_context'} = shift @_;
    }
    return $self->{'_context'};
}


sub config_get {
    my $self = shift @_;

    return $self->config->get( @{$self->context}, @_ );
}


sub config_set {
    my $self = shift @_;

    return $self->config->set( @{$self->context}, @_ );
}


1;
