# This is the 'Local' implementation of Meadow

package Bio::EnsEMBL::Hive::Meadow::LOCAL;

use strict;
use Sys::Hostname;

use base 'Bio::EnsEMBL::Hive::Meadow';

sub count_running_workers {
    my $self = shift @_;

    my $cmd = 'ps -a | grep runWorker.pl | grep -v grep | wc -l';
    my $run_count = qx/$cmd/;
    chomp($run_count);

    return $run_count;
}

sub responsible_for_worker {
    my ($self, $worker) = @_;

    return ($worker->beekeeper() eq $self->type()) and ($worker->host eq hostname());
}

sub check_worker_is_alive {
    my ($self, $worker) = @_;

    my $cmd = 'ps '. $worker->process_id . ' 2>&1 | grep ' . $worker->process_id;
    my $is_alive = qx/$cmd/;
    return $is_alive;
}

sub kill_worker {
    my ($self, $worker) = @_;

    if( $self->responsible_for_worker($worker) ) {
        if($self->check_worker_is_alive($worker)) {
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
    my ($self, $worker_cmd, $worker_count, $iteration) = @_;

    my $cmd = "$worker_cmd &";

    foreach (1..$worker_count) {
        print "SUBMITTING_CMD:\t\t$cmd\n";
        system($cmd);
    }
}

1;
