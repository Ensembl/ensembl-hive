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
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'
use Bio::EnsEMBL::Hive::Utils ('find_submodules');


sub meadow_class_path {

    return 'Bio::EnsEMBL::Hive::Meadow';
}


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my $amch = $self->available_meadow_classes_hash();

        # make sure modules are loaded and available ones are checked prior to setting the current one
    foreach my $meadow_class (@{ find_submodules( $self->meadow_class_path ) }) {
        eval "require $meadow_class";
        if($meadow_class->available) {
            $amch->{$meadow_class}=1;
        }
    }

    my ($current_meadow_class) =
         rearrange([qw(current_meadow_class) ], @_);

    $self->current_meadow_class($current_meadow_class) if(defined($current_meadow_class));

    return $self;
}


sub available_meadow_classes_hash {
    my $self = shift @_;

    if(@_) {
        $self->{_available_meadow_classes_hash} = shift @_;
    }   
    return $self->{_available_meadow_classes_hash} ||= {};
}


sub get_available_meadow_classes_list {     # this beautiful one-liner pushes $local to the bottom of the list
    my $self = shift @_;

    my $local = $self->meadow_class_path . '::LOCAL';

    return [ sort { ($a eq $local) or -($b eq $local) } keys %{ $self->available_meadow_classes_hash } ];
}


sub current_meadow_class {
    my $self = shift @_;

    if(@_) {
        my $current_meadow_class = shift @_;

        unless($current_meadow_class=~/::/) {       # extend the shorthand into full class name if needed
            $current_meadow_class = $self->meadow_class_path .'::'. uc($current_meadow_class);
        }

        if( $self->available_meadow_classes_hash->{$current_meadow_class} ) {   # store if available
            $self->{_current_meadow_class} = $current_meadow_class;
        } else {
            die "Meadow '$current_meadow_class' does not seem to be available on this machine, please investigate";
        }
    }
    return $self->{_current_meadow_class} ||= $self->get_available_meadow_classes_list->[0];     # take the first from preference list
}


sub guess_current_type_pid_exechost {
    my $self = shift @_;

    my ($type, $pid);
    foreach my $meadow_class (@{ $self->get_available_meadow_classes_list }) {
        eval {
            $pid = $meadow_class->get_current_worker_process_id();
            $type = $meadow_class->type();
        };
        unless($@) {
            last;
        }
    }
    unless($pid) {
        die "Could not determine the Meadow, please investigate";
    }

    my $exechost = hostname();

    return ($type, $pid, $exechost);
}


1;

