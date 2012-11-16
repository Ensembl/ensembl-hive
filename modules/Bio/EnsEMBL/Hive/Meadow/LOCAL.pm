# This is the 'Local' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LOCAL;

use strict;
use Sys::Hostname;

use base ('Bio::EnsEMBL::Hive::Meadow');


sub name {  # also called to check for availability; for the moment assume LOCAL meadow is always available

    return (split(/\./, hostname))[0];     # only take the first name
}


sub get_current_worker_process_id {
    my ($self) = @_;

    return $$;
}


sub count_pending_workers_by_rc_name {
    my ($self) = @_;

    return ({}, 0);     # LOCAL has no concept of pending workers
}


sub count_running_workers {
    my $self = shift @_;

    my $cmd = 'ps x | grep runWorker.pl | grep -v "grep runWorker.pl" | wc -l';
    my $run_count = qx/$cmd/;
    chomp($run_count);

    return $run_count;
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

        my $status = {
            'R' => 'RUN',   # running

            'S' => 'RUN',   # sleeping (sleeping for less than 20 sec on a Mac)
            'I' => 'RUN',   # Mac: idle (sleeping for more than 20 sec)

            'D' => 'RUN',   # Linux: uninterruptible sleep, usually IO
            'U' => 'RUN',   # Mac: uninterruptible wait

            'T' => 'SSUSP'  # stopped process
        }->{ substr($pre_status,0,1) }; # only take the first character because of Mac's additional modifiers

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
    my $worker = pop @_;

    my $cmd = 'kill -9 '.$worker->process_id();
    system($cmd);
}


sub submit_workers {
    my ($self, $worker_cmd, $worker_count, $iteration, $rc_name, $rc_parameters) = @_;

    my $cmd = "$worker_cmd &";

    foreach (1..$worker_count) {
        print "SUBMITTING_CMD:\t\t$cmd\n";
        system( $cmd );
    }
}

1;
