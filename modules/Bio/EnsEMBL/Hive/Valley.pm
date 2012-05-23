=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Valley

=head1 SYNOPSIS

=head1 DESCRIPTION

    A Valley represents a collection of available Meadows.

    Certain methods fit better with the concept of Valley -
    such as identifying all dead workers, or killing a particular one given worker_id.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::Valley;

use strict;
use warnings;
use Sys::Hostname;
use Bio::EnsEMBL::Hive::Utils ('find_submodules');


sub meadow_class_path {

    return 'Bio::EnsEMBL::Hive::Meadow';
}


sub new {
    my ($class, $current_meadow_type) = @_;

    my $self = bless {}, $class;

    my $amch = $self->available_meadow_hash( {} );

        # make sure modules are loaded and available ones are checked prior to setting the current one
    foreach my $meadow_class (@{ find_submodules( $self->meadow_class_path ) }) {
        eval "require $meadow_class";
        if($meadow_class->name) {
            $amch->{$meadow_class->type} = $meadow_class->new();
        }
    }

    $self->set_current_meadow_type($current_meadow_type);     # run this method even if $current_meadow_type was not specified

    return $self;
}


sub available_meadow_hash {
    my $self = shift @_;

    if(@_) {
        $self->{_available_meadow_hash} = shift @_;
    }   
    return $self->{_available_meadow_hash};
}


sub get_available_meadow_list {     # this beautiful one-liner pushes $local to the bottom of the list
    my $self = shift @_;

    my $local = $self->meadow_class_path . '::LOCAL';

    return [ sort { (ref($a) eq $local) or -(ref($b) eq $local) } values %{ $self->available_meadow_hash } ];
}


sub set_current_meadow_type {
    my ($self, $current_meadow_type) = @_;

    if($current_meadow_type) {
        if( my $current_meadow = $self->available_meadow_hash->{$current_meadow_type} ) {   # store if available
            $self->{_current_meadow} = $current_meadow;
        } else {
            die "Meadow '$current_meadow_type' does not seem to be available on this machine, please investigate";
        }
    } else {
        $self->{_current_meadow} = $self->get_available_meadow_list->[0];     # take the first from preference list
    }
}


sub get_current_meadow {
    my $self = shift @_;

    return $self->{_current_meadow};
}


sub find_available_meadow_responsible_for_worker {
    my ($self, $worker) = @_;

    if( my $meadow = $self->available_meadow_hash->{$worker->meadow_type} ) {
        if($meadow->name eq $worker->meadow_name) {
            return $meadow;
        }
    }
    return undef;
}


sub whereami {
    my $self = shift @_;

    my ($meadow_type, $meadow_name, $pid);
    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        eval {
            $pid         = $meadow->get_current_worker_process_id();
            $meadow_type = $meadow->type();
            $meadow_name = $meadow->name();
        };
        unless($@) {
            last;
        }
    }
    unless($pid) {
        die "Could not determine the Meadow, please investigate";
    }

    my $exechost = hostname();

    return ($meadow_type, $meadow_name, $pid, $exechost);
}


1;

