# This is the 'Local' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LOCAL;

use strict;
use Sys::Hostname;

use base ('Bio::EnsEMBL::Hive::Meadow');

sub get_current_worker_process_id {
    my ($self) = @_;

    return $$;
}

sub count_running_workers {
    my $self = shift @_;

    my $cmd = 'ps x | grep runWorker.pl | grep -v "grep runWorker.pl" | wc -l';
    my $run_count = qx/$cmd/;
    chomp($run_count);

    return $run_count;
}

sub responsible_for_worker {
    my ($self, $worker) = @_;

    return ( $self->SUPER::responsible_for_worker($worker) && ($worker->host eq hostname()) );
}

sub status_of_all_our_workers { # returns a hashref
    my ($self) = @_;

    my $cmd = 'ps x -o state,pid,command -w -w | grep runWorker.pl | grep -v "grep runWorker.pl" ';

        # FIXME: if we want to incorporate Meadow->pipeline_name() filtering here,
        #        a dummy parameter to the runWorker.pl should probably be introduced
        #        for 'ps' to be able to externally differentiate between local workers
        #        working for different hives
        #        (but at the moment such a feature is unlikely to be be in demand).

    my %status_hash = ();
    foreach my $line (`$cmd`) {
        my ($pre_status, $worker_pid, $job_name) = split(/\s+/, $line);

        my $status = { 'R' => 'RUN', 'S' => 'RUN', 'D' => 'RUN', 'T' => 'SSUSP' }->{$pre_status};

        # Note: you can locally 'kill -19' a worker to suspend it and 'kill -18' a worker to resume it

        $status_hash{$worker_pid} = $status;
    }
    return \%status_hash;
}

sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $cmd = qq{ps x | grep $wpid | grep -v 'grep $wpid'};
    my $is_alive_and_mine = qx/$cmd/;

    return $is_alive_and_mine;
}

sub kill_worker {
    my ($self, $worker) = @_;

    if( $self->responsible_for_worker($worker) ) {
        if($self->check_worker_is_alive_and_mine($worker)) {
            my $cmd = 'kill -9 '.$worker->process_id();
            system($cmd);
        } else {
            warn 'Cannot kill worker '.$worker->process_id().' because it is not running';
        }
    } else {
        warn 'Cannot kill worker '.$worker->process_id().'@'.$worker->host.' it is probably running on a different host';
    }
}

sub submit_workers {
    my ($self, $iteration, $worker_cmd, $worker_count, $rc_id, $rc_parameters) = @_;

    my $cmd = "$worker_cmd -rc_id $rc_id &";    # $rc_parameters are ignored for the time being

    foreach (1..$worker_count) {
        print "SUBMITTING_CMD:\t\t$cmd\n";
        system($cmd);
    }
}

1;
