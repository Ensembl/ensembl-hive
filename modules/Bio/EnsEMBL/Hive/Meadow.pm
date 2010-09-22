# A Meadow is an abstract interface for one of several implementations of Workers' process manager.
#
# A Meadow knows how to check&change the actual status of Workers

package Bio::EnsEMBL::Hive::Meadow;

use Sys::Hostname;
use Bio::EnsEMBL::Hive::Meadow::LSF;
use Bio::EnsEMBL::Hive::Meadow::LOCAL;

use strict;

sub new {
    my $class = shift @_;

    unless($class=~/::/) {
        $class = 'Bio::EnsEMBL::Hive::Meadow'.$class;
    }

    return bless { @_ }, $class;
}

sub guess_current_type_pid_exechost {
    my $self = shift @_;

    my ($type, $pid);
    eval {
        $pid  = Bio::EnsEMBL::Hive::Meadow::LSF->get_current_worker_process_id();
        $type = 'LSF';
    };
    if($@) {
        $pid  = Bio::EnsEMBL::Hive::Meadow::LOCAL->get_current_worker_process_id();
        $type = 'LOCAL';
    }

    my $exechost = hostname();

    return ($type, $pid, $exechost);
}

sub type { # should return 'LOCAL' or 'LSF'
    return (reverse split(/::/, ref(shift @_)))[0];
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

    return $worker->beekeeper() eq $self->type();
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

sub total_running_workers_limit { # if set and ->can('count_running_workers'),
                                  # provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_total_running_workers_limit'} = shift @_;
    }
    return $self->{'_total_running_workers_limit'};
}

sub pending_adjust { # if set and ->can('count_pending_workers'),
                     # provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_pending_adjust'} = shift @_;
    }
    return $self->{'_pending_adjust'};
}

sub submitted_workers_limit { # if set, provides a cut-off on the number of workers being submitted
    my $self = shift @_;

    if(scalar(@_)) { # new value is being set (which can be undef)
        $self->{'_submitted_workers_limit'} = shift @_;
    }
    return $self->{'_submitted_workers_limit'};
}

sub limit_workers {
    my ($self, $worker_count) = @_;

    if($self->can('count_pending_workers') and $self->pending_adjust()) {
        my $pending_count = $self->count_pending_workers();

        $worker_count -= $pending_count;
    }

    if(defined(my $submit_limit = $self->submitted_workers_limit)) {
        if($submit_limit < $worker_count) {

            $worker_count = $submit_limit;
        }
    }

    if($self->can('count_running_workers') and defined(my $total_limit = $self->total_running_workers_limit)) {
        my $available_slots = $total_limit - $self->count_running_workers();
        if($available_slots < $worker_count) {

            $worker_count = $available_slots;
        }
    }

    $worker_count = 0 if ($worker_count<0);

    return $worker_count;
}

1;
