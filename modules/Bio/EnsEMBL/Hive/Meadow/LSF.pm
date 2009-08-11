# This is the 'LSF' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;

use base 'Bio::EnsEMBL::Hive::Meadow';

sub count_pending_workers {
    my ($self) = @_;

    my $cmd = "bjobs -w ";
    if(my $pipeline_name = $self->pipeline_name()) {
        $cmd .= " | grep '${pipeline_name}-HL'";
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
        $cmd .= " | grep '${pipeline_name}-HL'";
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

sub lsf_options {
    my $self = shift @_;

    if(scalar(@_)) {
        $self->{'_lsf_options'} = shift @_;
    }
    return $self->{'_lsf_options'} || '';
}

sub submit_workers {
    my ($self, $worker_cmd, $worker_count, $iteration) = @_;

    my $job_name    = $self->generate_job_name($worker_count, $iteration);
    my $lsf_options = $self->lsf_options();

    my $cmd = "bsub -o /dev/null -J\"${job_name}\" $lsf_options $worker_cmd";

    print "SUBMITTING_CMD:\t\t$cmd\n";
    system($cmd);
}

1;
