=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LOCAL

=head1 DESCRIPTION

    This is the 'Local' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

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

sub deregister_local_process {}   # Nothing to do

sub _command_line_to_extract_all_running_workers {
    my ($self) = @_;

    my $job_name_prefix = $self->job_name_prefix();

        # Make sure we have excluded both 'awk' itself and commands like "less runWorker.pl" :
    return sprintf(q{ps ex -o state,user,pid,command -w -w | grep 'EHIVE_SUBMISSION_NAME=%s' | awk '(/runWorker.pl/ && ($4 ~ /perl$/) )'}, $job_name_prefix);
}


sub status_of_all_our_workers { # returns an arrayref
    my ($self) = @_;

    my $cmd = $self->_command_line_to_extract_all_running_workers;

    my @status_list = ();
    foreach my $line (`$cmd`) {
        my ($pre_status, $meadow_user, $worker_pid, @job_name) = split(/\s+/, $line);

        my $status = {
            'R' => 'RUN',   # running

            'S' => 'RUN',   # sleeping (sleeping for less than 20 sec on a Mac)
            'I' => 'RUN',   # Mac: idle (sleeping for more than 20 sec)

            'D' => 'RUN',   # Linux: uninterruptible sleep, usually IO
            'U' => 'RUN',   # Mac: uninterruptible wait

            'T' => 'SSUSP'  # stopped process
        }->{ substr($pre_status,0,1) }; # only take the first character because of Mac's additional modifiers

        # Note: you can locally 'kill -19' a worker to suspend it and 'kill -18' a worker to resume it

        my $rc_name = '__unknown_rc_name__';
        if (join(' ', @job_name) =~ / -rc_name (\S+)/) {
            $rc_name = $1;
        }

        push @status_list, [$worker_pid, $meadow_user, $status, $rc_name];
    }
    return \@status_list;
}


sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $cmd = qq{ps x | grep $wpid | grep -v 'grep $wpid'};
    my $is_alive_and_mine = qx/$cmd/;

    return $is_alive_and_mine;
}


sub kill_worker {
    my ($self, $worker, $fast) = @_;

    system('kill', '-9', $worker->process_id());
}


sub submit_workers {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my ($submit_stdout_file, $submit_stderr_file);

    if($submit_log_subdir) {
        $submit_stdout_file = $submit_log_subdir . "/log_${rc_name}_${iteration}_\$\$.out";
        $submit_stderr_file = $submit_log_subdir . "/log_${rc_name}_${iteration}_\$\$.err";
    } else {
        $submit_stdout_file = '/dev/null';
        $submit_stderr_file = '/dev/null';
    }

    my $job_name = $self->job_array_common_name($rc_name, $iteration);
    $ENV{EHIVE_SUBMISSION_NAME} = $job_name;

    my $cmd = "$worker_cmd > $submit_stdout_file 2> $submit_stderr_file &";

    print "Executing [ ".$self->signature." ] x$required_worker_count \t\t$cmd\n";
    foreach (1..$required_worker_count) {
        system( $cmd ) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax;
    }
}

1;
