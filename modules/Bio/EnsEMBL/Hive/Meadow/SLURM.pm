=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::SLURM

=head1 DESCRIPTION

    This is the 'SLURM' implementation of an EnsEMBL eHive Meadow.

=head1 Compatibility

    Module version 5.5 is compatible with SLURM version slurm 23.02.7

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:
    http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users
    to discuss Hive-related questions or to be notified of our updates

=cut

package Bio::EnsEMBL::Hive::Meadow::SLURM;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils qw(split_for_bash timeout);
use DateTime::Format::ISO8601;
use File::Temp qw(tempdir);
use Scalar::Util qw(looks_like_number);
use Time::Piece;
use Time::Seconds;
use IPC::Cmd qw(run);

use parent 'Bio::EnsEMBL::Hive::Meadow';

# Semantic version of the Meadow interface:
#   change the Major version whenever an incompatible change is introduced,
#   change the Minor version whenever the interface is extended, but compatibility is retained.
# Module version 5.5 is compatible with Slurm 23.02.7
our $VERSION = '5.5';

=head name

   Args:       : None
   Description : Return cluster name
   Return      : "slurm" if available, else undef
   Returntype  : String

=cut

# For SLURM, a cluster name will only be available when running in a federation,
# so we always return "slurm".
# Since this is also called to check for availability, assume Slurm is available
# if sinfo gives a version and a non-zero node count.
sub name {
    # List the slurm version and the cluster node count like "23.02.7:197"
    my $sinfo = `sinfo -ho "%v:%D" 2>/dev/null`;
    $sinfo =~ /^(\d+)(?:\.\d+)*:(\d+)$/;
    my $slurm_version = $1;
    my $node_count = $2;

    if ($slurm_version and $node_count and $slurm_version >= 23 and $node_count > 0) {
        return "slurm";
    }
}

# Override method
sub _init_meadow {
    my ($self, $config) = @_;
    $self->SUPER::_init_meadow($config);

    # Override user config. On Slurm, the tmp dirs are always cleaned up. It is
    # not necessary to set this. To clean up, beekeeper will try an SSH log in
    # to each node. This does not work and only produces error messages.
    $self->config_set('CleanupTempDirectoryKilledWorkers', 0);
}

=head count_pending_workers_by_rc_name

   Args:       : None
   Description : Counts the number of pending workers of the user
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : String

=cut

sub count_pending_workers_by_rc_name {
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();

    # Prefix for job is not implemented in Slurm, so need to get all
    # and parse it out
    my $cmd = "squeue --array --noheader --me --states='PENDING' --format='%j'";

    my @output = execute_command($cmd);

    my %pending_this_meadow_by_rc_name = ();
    my $total_pending_this_meadow = 0;

    foreach my $line (@output) {
        if ($line =~ /\b\Q$jnp\E(\S+)\-\d+(\[\d+\])?\b/) {
            $pending_this_meadow_by_rc_name{$1}++;
            $total_pending_this_meadow++;
        }
    }

    return (\%pending_this_meadow_by_rc_name, $total_pending_this_meadow);
} ## end sub count_pending_workers_by_rc_name

=head count_running_workers

   Args:       : None
   Description : Counts the number of pending workers of the user
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : String

=cut

sub count_running_workers {
    my $self = shift;

    my $jnp = $self->job_name_prefix();

    my $cmd = "squeue --array --noheader --me --states='RUNNING' --format='%j' | grep ^$jnp | wc -l";
    my $output = execute_command($cmd);

    $output =~ /(\d+)/;

    return $1;
}

=head status_of_all_our_workers()

   Args:       : None
   Description : Counts the number of pending workers of the user
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : Array [ worker_pid, user, status ]

=cut

sub status_of_all_our_workers {
    my $self = shift;

    my $jnp = $self->job_name_prefix();    # reederj_ehive_rosaprd_278-Hive-
    my @status_list = ();

    # PENDING, RUNNING, SUSPENDED, CANCELLED, COMPLETING, COMPLETED, CONFIGURING, FAILED,
    # TIMEOUT, PREEMPTED, NODE_FAIL, REVOKED and SPECIAL_EXIT

    my $cmd = "squeue --array --noheader --me --format='%i|%T|%u'";

    my @output = execute_command($cmd);

    foreach my $line (@output) {
        my ($worker_pid, $status, $user) = split(/\|/, $line);

        # TODO: not exactly sure what these are used for in the external code -
        # this is based on the LSF status codes that were ignored
        # Do not count COMPLETED or FAILED jobs.
        next if (($status eq 'COMPLETED') or ($status eq 'FAILED'));

        push @status_list, [$worker_pid, $user, $status];
    }
    return \@status_list;
} ## end sub status_of_all_our_workers

=head check_worker_is_alive_and_mine()

   Args:       : Bio::EnsEMBL::Hive::Worker
   Description : Checks if a worker is registered under the current logged in user.
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : String (value of squeue command )

=cut

sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $this_user = $ENV{'USER'};

    my $cmd = "squeue --noheader --me --job=$wpid";

    my $output = eval{execute_command($cmd)};

    return $output ? 1 : 0;
}

=head kill_worker()

   Args:       : None
   Description : Counts the number of pending workers of the user
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : Array [ worker_pid, user, status ]

=cut

sub kill_worker {
    my ($self, $worker, $fast) = @_;

    my $cmd = 'scancel ' . $worker->process_id();
    execute_command($cmd);
}

=head get_report_entries_for_process_ids()

   Args:       : None
   Description : Gathers stats for a specific set of workers via sacct.
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : Complex.

=cut

sub get_report_entries_for_process_ids {
    my $self = shift @_;    # make sure we get if off the way before splicing

    my %combined_report_entries = ();

    while (my $pid_batch = join(',', splice(@_, 0, 20))) {
        # can't fit too many pids on one shell cmdline

        # sacct -j 19661,19662,19663
        #  --units=M Display values in specified unit type. [KMGTP]
        my $cmd =
            "sacct -n -p --units=M --format JobName,JobID,ExitCode,MaxRSS," .
            "MaxDiskRead,CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End " .
            "-j $pid_batch";

            # print "DEBUG get_report_entries_for_process_ids() running cmd:\n\t$cmd\n";
        my $batch_of_report_entries = $self->parse_report_source_line($cmd);

        %combined_report_entries = (%combined_report_entries, %$batch_of_report_entries);
    }

    return \%combined_report_entries;
}

=head get_report_entries_for_process_ids()

   Args:       : None
   Description : Gathers statistics for jobs for a time interval by running sacct.
   Exception   : Dies if command to retrieve stats fails.
   Returntype  : Complex.
   Caller      : Gets called from load_resource_usage.pl

=cut

sub get_report_entries_for_time_interval {
    my ($self, $from_time, $to_time, $username) = @_;

    my $from_timepiece = Time::Piece->strptime($from_time, '%Y-%m-%d %H:%M:%S');
    $from_time = $from_timepiece->strftime('%Y-%m-%dT%H:%M');

    my $to_timepiece = Time::Piece->strptime($to_time, '%Y-%m-%d %H:%M:%S') + 2 * ONE_MINUTE;
    $to_time = $to_timepiece->strftime('%Y-%m-%dT%H:%M');

    # sacct -s CA,CD,CG,F -S 2018-02-27T16:48 -E 2018-02-27T16:50
    my $cmd = "sacct -n -p --units=M -s CA,CD,F,OOM --format JobName,JobID,ExitCode,MaxRSS,MaxDiskRead," .
        "CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End -S $from_time -E $to_time";

        # print "DEBUG get_report_entries_for_time_interval() running cmd:\n\t$cmd\n";

    my $batch_of_report_entries = $self->parse_report_source_line($cmd);

    return $batch_of_report_entries;
}

=head parse_report_source_line()

   Args:       : Command ( sacct )
   Description : Parses the resource counts the number of pending workers of the user
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : Href

=cut

sub parse_report_source_line {
    my ($self, $bacct_source_line) = @_;

    my $jnp = $self->job_name_prefix();    # reederj_ehive_rosaprd_278-Hive-

    my @lines = execute_command($bacct_source_line);

    my %report_entry = ();
    my %job_id_to_state;

    for my $row (@lines) {
        my @col = split(/\|/, $row);

        my $job_name = $col[0];     # JobName - for explanation please look at sacct command
        my $job_id = $col[1];       # JobID
        my $exit_code = $col[2];    # ExitCode
        my $mem_used = $col[3];     # MaxRSS in units=M
                                    #my $reserved_time = $col[4];   # Reserved / pending time ...
        my $reserved_time = 0;
        my $max_disk_read = $col[4];       # MaxDiskRead
        my $total_cpu = $col[5];           # CPUTimeRAW
        my $elapsed = $col[6];             # ElapsedRAW
        my $state = $col[7];               # State
        my $exception_status = $col[8];    # DerivedExitCode
        my $endtime = $col[9];

        my $datetime = DateTime::Format::ISO8601->parse_datetime($endtime);

        # print "DEBUG: $job_id\t$state\n";

        # parse the correct state
        if ($job_name =~ m/$jnp/) {
            $job_id_to_state{$job_id} = $state;
        }

        next unless $job_name =~ m/batch/;
        $job_id =~ s/\.batch//;

        $mem_used      =~ s/M$//;    # results are reported in Megabytes
        $max_disk_read =~ s/M$//;    # results are reported in Megabytes

        if ($reserved_time =~ /:/) {
            my $reserved_timepiece = Time::Piece->strptime($reserved_time, '%H:%M:%S');
            $reserved_time =
                $reserved_timepiece->hour*3600 +
                $reserved_timepiece->minute*60 +
                $reserved_timepiece->second;
        }

        # get previously parsed status ( slurm returns 3 rows of statuses which are different ! )
        my $cause_of_death = get_cause_of_death($job_id_to_state{$job_id});
        $exception_status = $cause_of_death;

        $report_entry{$job_id} = {
            # entries for 'worker' table:
            'when_died'      => $datetime->date . ' ' . $datetime->hms,
            'cause_of_death' => $cause_of_death,

            # entries for 'worker_resource_usage' table:
            'exit_status'      => $exit_code,
            'exception_status' => $exception_status,
            'mem_megs'         => $mem_used,         # mem_in_units, returnd by sacct with --units=M
            'swap_megs'        => $max_disk_read,    # swap_in_units
            'pending_sec'      => $reserved_time || 0,
            'cpu_sec'          => $total_cpu,
            'lifespan_sec'     => $elapsed,
        };
    } ## end for my $row (@$lines)
    return \%report_entry;
} ## end sub parse_report_source_line

=head submit_workers_return_meadow_pids()

   Args:       : Command ( sacct )
   Comment     : # Works with Slurm 17.02.9
   Description : Runs sbatch to submit workers to SLURM
   Exception   : Dies if command to retrieve pending workers fails.
   Returntype  : Href

=cut

sub submit_workers_return_meadow_pids {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name,
        $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my $job_array_common_name = $self->job_array_common_name($rc_name, $iteration);

    # Flag if we should submit a job array or not
    my $array_required = $required_worker_count > 1;

    my $job_array_spec = "1-${required_worker_count}";
    my $meadow_specific_submission_cmd_args = $self->config_get('SubmissionOptions');

    my ($submit_stdout_file, $submit_stderr_file);

    if ($submit_log_subdir) {
        $submit_stdout_file = $submit_log_subdir . "/log_${rc_name}_%A_%a.out";
        $submit_stderr_file = $submit_log_subdir . "/log_${rc_name}_%A_%a.err";
    } else {
        $submit_stdout_file = '/dev/null';
        $submit_stderr_file = '/dev/null';
    }

    #No equivalent in sbatch, but can be accomplished with stdbuf -oL -eL
    #$ENV{'LSB_STDOUT_DIRECT'} = 'y';  # unbuffer the output of the bsub command

    #Note: job arrays share the same name in slurm and are 0-based, but this may still work
    my @cmd;
    if ($array_required eq "1") {
        # We have to submit a job array - this will change the job ids in slurm to <job_id>_ARRAY

        @cmd = (
            'sbatch',
            '--parsable',
            '-o', $submit_stdout_file,
            '-e', $submit_stderr_file,
            # inform SLURM we submit an ARRAY
            # jobs submitted with 'sbatch -a ' get different ids back when executing
            # 'squeue --array -h -u <user> -o '%i|%T|%u|%A' later
            '-a', $job_array_spec,
            '-J', $job_array_common_name,
            split_for_bash($rc_specific_submission_cmd_args),
            split_for_bash($meadow_specific_submission_cmd_args),
            '--wrap',
            $worker_cmd,
        );
    } else {
        @cmd = (
            'sbatch',
            '--parsable',
            '-o', $submit_stdout_file,
            '-e', $submit_stderr_file,
            '-J', $job_array_common_name,
            split_for_bash($rc_specific_submission_cmd_args),
            split_for_bash($meadow_specific_submission_cmd_args),
            '--wrap',
            $worker_cmd,
        );

    }

    print "Executing [ " . $self->name . " ]: " . join(' ', @cmd) . "\n";

    my @output = execute_command(\@cmd);

    unless ($output[0] =~ m/(\d+)/) {
        die "Could not find job id in sbatch output";
    }

    my $slurm_job_id = $output[0];

    if (looks_like_number($slurm_job_id)) {
        my $return_value;

        # Modify the return values depending on the submission type: single job vs job array
        # as these have different indexes:
        # array jobs: [54729315_1, 54729315_2]
        # single job: [54728975]
        if ($array_required) {
            $return_value = [map {$slurm_job_id . '_' . $_ . ''} (1 .. $required_worker_count)];
        } else {
            $return_value = [$slurm_job_id];
        }

        return $return_value;
    } else {
        die "Unexpected output for sbatch command. Command: '@cmd'; STDOUT: '" . (join "\n", @output) . "'";
    }
} ## end sub submit_workers_return_meadow_pids

sub execute_command {
    # command can be an arrayref or a string
    my $cmd = shift;

    # Timeout for slurm commands
    my $timeout = 120;

    my ($success, $error_message, undef, $stdout_buf, $stderr_buf) =
        run(command => $cmd, verbose => 0, timeout => $timeout);

    my $output;
    if ($success) {
        $output = join("", @$stdout_buf);
    } else {
        die "Failed to execute command '$cmd'. Error: '$error_message', " .
            "STDOUT: '@$stdout_buf', STDERR: '@$stderr_buf'";
    }
    return wantarray ? split(/\n/, $output // "") : $output;
}

sub get_current_worker_process_id {
    my ($self) = @_;

    my $slurm_jobid = $ENV{'SLURM_JOB_ID'};
    my $slurm_array_job_id = $ENV{'SLURM_ARRAY_JOB_ID'};
    my $slurm_array_task_id = $ENV{'SLURM_ARRAY_TASK_ID'};

    # We have a slurm job
    if (defined($slurm_jobid)) {
        # We have an array job
        if (defined($slurm_array_job_id) and defined($slurm_array_task_id)) {
            return "$slurm_array_job_id\_$slurm_array_task_id";
        } else {
            return $slurm_jobid;
        }
    } else {
        die "Could not establish the process_id";
    }
}

sub deregister_local_process {
    my ($self) = @_;

    delete $ENV{'SLURM_JOB_ID'};
    delete $ENV{'SLURM_ARRAY_JOB_ID'};
    delete $ENV{'SLURM_ARRAY_TASK_ID'};
}

=head get_cause_of_death()

   Args:       : Slurm job state
   Description : Translates a SLURM job state into an eHive cause-of-death
   Exception   : None
   Returntype  : String

=cut

sub get_cause_of_death {
    my ($state) = @_;

    my %slurm_status_2_cod = (
        'TIMEOUT'       => 'RUNLIMIT',
        'FAILED'        => 'CONTAMINATED',
        'OUT_OF_MEMORY' => 'MEMLIMIT',
        'CANCELLED'     => 'KILLED_BY_USER',
    );
    my $cod = $slurm_status_2_cod{$state};
    unless ($cod) {
        $cod = "UNKNOWN";
    }
    return $cod;
}

1;
