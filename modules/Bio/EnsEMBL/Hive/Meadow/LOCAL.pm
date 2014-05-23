=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LOCAL

=head1 DESCRIPTION

    This is the 'Local' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Meadow::LOCAL;

use strict;
use warnings;
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
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my $cmd = "$worker_cmd &";

    foreach (1..$required_worker_count) {
        print "SUBMITTING_CMD:\t\t$rc_specific_submission_cmd_args $cmd\n";
        system( $cmd );
    }
}

1;
