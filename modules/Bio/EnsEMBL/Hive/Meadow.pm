# A Meadow is an abstract interface for one of several implementations of Workers' process manager.
#
# A Meadow knows how to check&change the actual status of Workers

package Bio::EnsEMBL::Hive::Meadow;

use strict;
use warnings;


sub new {
    my $class = shift @_;

    return bless { @_ }, $class;
}


sub type { # should return 'LOCAL' or 'LSF'
    my $class = shift @_;

    $class = ref($class) if(ref($class));

    return (reverse split(/::/, $class ))[0];
}


sub toString {
    my $self = shift @_;

    return "Meadow[type='".$self->type."', name='".$self->name."']";
}


sub pipeline_name { # if set, provides a filter for job-related queries
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_pipeline_name'} = shift @_;
    }
    return $self->{'_pipeline_name'};
}

sub meadow_options {    # general options that different Meadows can plug into the submission command
    my $self = shift @_;

    if(scalar(@_)) {
        $self->{'_meadow_options'} = shift @_;
    }
    return $self->{'_meadow_options'} || '';
}

sub job_name_prefix {
    my $self = shift @_;

    return ($self->pipeline_name() ? $self->pipeline_name().'-' : '') . 'Hive';
}

sub generate_job_name {
    my ($self, $worker_count, $iteration, $rc_id) = @_;
    $rc_id ||= 0;

    return $self->job_name_prefix()
        ."${rc_id}_${iteration}"
        . (($worker_count > 1) ? "[1-${worker_count}]" : '');
}

sub responsible_for_worker {
    my ($self, $worker) = @_;

    return ($worker->meadow_type eq $self->type) && ($worker->meadow_name eq $self->name);
}

sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}

sub kill_worker {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}

# --------------[(combinable) means of adjusting the number of submitted workers]----------------------

sub total_running_workers_default_max {   # no default by default :)

    return undef;
}

sub total_running_workers_max { # if set and ->can('count_running_workers'),
                                  # provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_total_running_workers_max'} = shift @_;
    }
    return $self->{'_total_running_workers_max'} || $self->total_running_workers_default_max();
}

sub pending_adjust { # if set and ->can('count_pending_workers_by_rc_id'),
                     # provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_pending_adjust'} = shift @_;
    }
    return $self->{'_pending_adjust'};
}

sub submit_workers_max { # if set, provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_submit_workers_max'} = shift @_;
    }
    return $self->{'_submit_workers_max'};
}

1;
