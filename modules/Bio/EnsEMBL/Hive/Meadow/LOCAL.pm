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

use Bio::EnsEMBL::Hive::Utils ('split_for_bash');
use Bio::EnsEMBL::Hive::Utils::RedirectStack;

use base ('Bio::EnsEMBL::Hive::Meadow');


our $VERSION = '5.0';       # Semantic version of the Meadow interface:
                            #   change the Major version whenever an incompatible change is introduced,
                            #   change the Minor version whenever the interface is extended, but compatibility is retained.


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

        # Make sure we have excluded both 'awk' itself and commands like "less runWorker.pl" :
    return q{ps ex -o state,user,pid,command -w -w | awk '((/runWorker.pl/ || /beekeeper.pl/) && ($4 ~ /perl$/) )'};
}


sub status_of_all_our_workers { # returns an arrayref
    my ($self) = @_;

    my $cmd = $self->_command_line_to_extract_all_running_workers;
    my $job_name_prefix = $self->job_name_prefix();

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

        # Exclude workers from other pipelines
        if (join(' ', @job_name) =~ / EHIVE_SUBMISSION_NAME=(\S+)/) {
            unless ($1 =~ /^$job_name_prefix/) {
                next;
            }
        }

        push @status_list, [$worker_pid, $meadow_user, $status];
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


sub submit_workers_return_meadow_pids {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my @worker_cmd_components = split_for_bash($worker_cmd);  # FIXME: change the interface so that $worker_cmd itself is passed in as ARRAYref

    my $job_name = $self->job_array_common_name($rc_name, $iteration);
    $ENV{EHIVE_SUBMISSION_NAME} = $job_name;

    my @children_pids = ();

    warn "Spawning [ ".$self->signature." ] x$required_worker_count \t\t$worker_cmd\n";

    foreach my $idx (1..$required_worker_count) {
        my $child_pid = fork;
        if(!defined( $child_pid )) {    # in the parent, fork() failed:
            die "Parent($$): fork failed";
        } elsif($child_pid > 0) {      # in the parent, fork() succeeded:
            push @children_pids, $child_pid;
        } else {    # in the child:
            my ($rs_stdout, $rs_stderr);

            my $submit_stdout_file = $submit_log_subdir ? $submit_log_subdir . "/log_${rc_name}_${iteration}_$$.out" : '/dev/null';
            my $submit_stderr_file = $submit_log_subdir ? $submit_log_subdir . "/log_${rc_name}_${iteration}_$$.err" : '/dev/null';
#            warn "Child($$) #$idx, about to redirect outputs to $submit_stdout_file and $submit_stderr_file\n";

            $rs_stdout = Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDOUT);
            $rs_stderr = Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDERR);
            $rs_stdout->push( $submit_stdout_file );
            $rs_stderr->push( $submit_stderr_file );
#            warn "Child($$) #$idx, about to exec.\n";

            unless( exec(@worker_cmd_components) ) {

                if( $submit_log_subdir ) {
                    $rs_stdout->pop();
                    $rs_stderr->pop();
                }
                die "Child($$) #$idx failed to exec, the error was '$!'.\n";
            }
        }
    }

    return \@children_pids;
}


sub run_on_host {   # Overrides Meadow::run_on_host
    my ($self, $meadow_host, $meadow_user, $command) = @_;
    # We can assume the current host is $meadow_host and bypass ssh
    return system(@$command);
}

1;
