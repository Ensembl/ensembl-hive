=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LOCAL

=head1 DESCRIPTION

    This is the 'Local' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

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
use Cwd ('cwd');
use Bio::EnsEMBL::Hive::Utils ('split_for_bash');

# --------------------------------------------------------------------------------------------------------------------
# <hack> What follows is a hack to extend the built-in exec() function that is called by Proc::Daemon .
#        The extended version also understands an ARRAYref as valid input and turns it into a LIST.
#        Thanks to this we can avoid calling an extra shell to interpret the command line being daemonized.
# --------------------------------------------------------------------------------------------------------------------

BEGIN {
    *Proc::Daemon::exec = sub {
        return ( ref($_[0]) eq 'ARRAY' ) ? CORE::exec( @{$_[0]} ) : CORE::exec( @_ );
    };
}

use Proc::Daemon 0.23;   # NB: this line absolutely must come after the BEGIN block that redefines exec(), or the trick will fail.

# --------------------------------------------------------------------------------------------------------------------
# </hack>
# --------------------------------------------------------------------------------------------------------------------


use base ('Bio::EnsEMBL::Hive::Meadow');


our $VERSION = '5.0';       # Semantic version of the Meadow interface:
                            #   change the Major version whenever an incompatible change is introduced,
                            #   change the Minor version whenever the interface is extended, but compatibility is retained.


sub name {  # also called to check for availability; for the moment assume LOCAL meadow is always available
    my ($self) = @_;

    return (split(/\./, $self->get_current_hostname() ))[0];     # only take the first name
}


sub get_current_worker_process_id {
    my ($self) = @_;

    return $$;
}

sub deregister_local_process {}   # Nothing to do

sub _command_line_to_extract_all_running_workers {
    my ($self) = @_;

        # Make sure we have excluded both 'awk' itself and commands like "less runWorker.pl" :
    return q{ps ex -o state,user,pid,command -w -w | awk '((/runWorker.pl/ || /beekeeper.pl/) && ($4 ~ /perl[[:digit:].]*$/) )'};
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
    my $is_alive_and_mine = kill 0, $wpid;

    return $is_alive_and_mine;
}


sub kill_worker {
    my ($self, $worker, $fast) = @_;

    my $exec_status = system('kill', '-9', $worker->process_id());
    return ( $exec_status >> 8 );
}


sub submit_workers_return_meadow_pids {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my $worker_cmd_components = [ split_for_bash($worker_cmd) ];

    my $job_name = $self->job_array_common_name($rc_name, $iteration);
    $ENV{EHIVE_SUBMISSION_NAME} = $job_name;

    my @children_pids = ();

    print "Spawning [ ".$self->signature." ] x$required_worker_count \t\t$worker_cmd\n";

    foreach my $idx (1..$required_worker_count) {

        my $child_pid = Proc::Daemon::Init( {
            $submit_log_subdir ? (
                child_STDOUT => $submit_log_subdir . "/log_${iteration}_${rc_name}_${idx}_$$.out",
                child_STDERR => $submit_log_subdir . "/log_${iteration}_${rc_name}_${idx}_$$.err",
            ) : (),     # both STD streams are sent to /dev/null by default
            work_dir     => cwd(),
            exec_command => [ $worker_cmd_components ],     # the AoA format is supported thanks to the BEGIN hack introduced in the beginning of this module.
        } );

        push @children_pids, $child_pid;
    }

    return \@children_pids;
}


sub run_on_host {   # Overrides Meadow::run_on_host
    my ($self, $meadow_host, $meadow_user, $command) = @_;
    # We can assume the current host is $meadow_host and bypass ssh
    return system(@$command);
}

1;
