# This is the 'LSF' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;

use base ('Bio::EnsEMBL::Hive::Meadow');

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

    my $jnp = $self->job_name_prefix();
    my $cmd = qq{bjobs -w -J '${jnp}*' -u all 2>/dev/null | grep -c PEND};

    my $pend_count = qx/$cmd/;
    chomp($pend_count);

    return $pend_count;
}

sub status_of_all_our_workers { # returns a hashref
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();
    my $cmd = qq{bjobs -w -J '${jnp}*' -u all 2>/dev/null | grep -v JOBID | grep -v DONE | grep -v EXIT};

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

sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $this_user = $ENV{'USER'};
    my $cmd = qq{bjobs $wpid -u $this_user 2>&1 | grep -v 'not found' | grep -v JOBID | grep -v EXIT};

    my $is_alive_and_mine = qx/$cmd/;
    return $is_alive_and_mine;
}

sub kill_worker {
    my ($self, $worker) = @_;

    if($self->check_worker_is_alive_and_mine($worker)) {
        my $cmd = 'bkill '.$worker->process_id();
        system($cmd);
    } else {
        warn 'Cannot kill worker '.$worker->process_id().' because it is not running';
    }
}

sub find_out_causes {
    my $self = shift @_;

    my %lsf_2_hive = (
        'TERM_MEMLIMIT' => 'MEMLIMIT',
        'TERM_RUNLIMIT' => 'RUNLIMIT',
        'TERM_OWNER'    => 'KILLED_BY_USER',
    );

    my %cod = ();

    while (my $pid_batch = join(' ', splice(@_, 0, 20))) {  # can't fit too many pids on one shell cmdline
        my $bacct_output = `bacct -l $pid_batch`;

        foreach my $section (split(/\-{10,}\s+/, $bacct_output)) {
            if($section=~/^Job <(\d+(?:\[\d+\]))>.+(TERM_MEMLIMIT|TERM_RUNLIMIT|TERM_OWNER): job killed/is) {
                $cod{$1} = $lsf_2_hive{$2};
            }
        }
    }

    return \%cod;
}

sub submit_workers {
    my ($self, $iteration, $worker_cmd, $worker_count, $rc_id, $rc_parameters) = @_;

    my $job_name       = $self->generate_job_name($worker_count, $iteration, $rc_id);
    my $meadow_options = $self->meadow_options();

    $ENV{'LSB_STDOUT_DIRECT'} = 'y';  # unbuffer the output of the bsub command

    my $cmd = qq{bsub -o /dev/null -J "${job_name}" $rc_parameters $meadow_options $worker_cmd -rc_id $rc_id};

    print "SUBMITTING_CMD:\t\t$cmd\n";
    system($cmd) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax
}

1;
