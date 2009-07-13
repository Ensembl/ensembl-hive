# This is the 'LSF' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;

use base 'Bio::EnsEMBL::Hive::Meadow';

sub count_pending_workers {
    my ($self, $name) = @_;

    my $cmd;
    if ($name) {
        $cmd = "bjobs -w | grep '$name-HL' | grep -c PEND";
    } else {
        $cmd = "bjobs -w | grep -c PEND";
    }
    my $pend_count = qx/$cmd/;
    chomp($pend_count);

    return $pend_count;
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
    my ($self, $worker_cmd, $worker_count, $jobname) = @_;

    if($worker_count>1) {
        $jobname .= "[1-${worker_count}]";
    }

    my $lsf_options = $self->lsf_options();
    my $cmd = "bsub -o /dev/null -J\"${jobname}\" $lsf_options $worker_cmd";

    print "SUBMITTING_CMD:\t\t$cmd\n";
    system($cmd);
}

1;
