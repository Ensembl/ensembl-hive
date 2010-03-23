# This is the 'LSF' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;

use base 'Bio::EnsEMBL::Hive::Meadow';

sub get_current_worker_process_id {
    my ($self) = @_;

    my $lsb_jobid    = $ENV{'LSB_JOBID'};
    my $lsb_jobindex = $ENV{'LSB_JOBINDEX'};

    if(defined($lsb_jobid) and defined($lsb_jobindex)) {
        if($lsb_jobindex>0) {
            return "$lsb_jobid\[$lsb_jobindex\]";
        } else {
            return $lsb_jobid;
        }
    } else {
        die "Could not establish the process_id";
    }
}

sub count_pending_workers {
    my ($self) = @_;

    my $cmd = "bjobs -w ";
    if(my $pipeline_name = $self->pipeline_name()) {
        $cmd .= " | grep '${pipeline_name}-Hive'";
    } else {
        $cmd .= " | grep Hive";
    }
    $cmd .= " | grep -c PEND";

    my $pend_count = qx/$cmd/;
    chomp($pend_count);

    return $pend_count;
}

sub status_of_all_my_workers { # returns a hashref
    my ($self) = @_;

    my $cmd = 'bjobs -w 2>&1 | grep -v "No unfinished job found" | grep -v JOBID | grep -v DONE | grep -v EXIT';
    if(my $pipeline_name = $self->pipeline_name()) {
        $cmd .= " | grep '${pipeline_name}-Hive'";
    } else {
        $cmd .= " | grep Hive";
    }

    my %status_hash = ();
    foreach my $line (`$cmd`) {
        my ($group_pid, $user, $status, $queue, $submission_host, $running_host, $job_name) = split(/\s+/, $line);

        my $worker_pid = $group_pid;
        if($job_name=~/(\[\d+\])/) {
            $worker_pid .= $1;
        }
            
        $status_hash{$worker_pid} = $status;
    }
    return \%status_hash;
}

sub check_worker_is_alive {
    my ($self, $worker) = @_;

    my $cmd = 'bjobs '. $worker->process_id . ' 2>&1 | grep -v "not found" | grep -v JOBID | grep -v EXIT';
    my $is_alive = qx/$cmd/;
    return $is_alive;
}

sub kill_worker {
    my ($self, $worker) = @_;

    if($self->check_worker_is_alive($worker)) {
        my $cmd = 'bkill '.$worker->process_id();
        system($cmd);
    } else {
        warn 'Cannot kill worker '.$worker->process_id().' because it is not running';
    }
}

sub submit_workers {
    my ($self, $iteration, $worker_cmd, $worker_count, $rc_id, $rc_parameters) = @_;

    my $job_name       = $self->generate_job_name($worker_count, $iteration, $rc_id);
    my $meadow_options = $self->meadow_options();

    my $cmd = "bsub -o /dev/null -J\"${job_name}\" $rc_parameters $meadow_options $worker_cmd -rc_id $rc_id";

    print "SUBMITTING_CMD:\t\t$cmd\n";
    system($cmd) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax
}

1;
