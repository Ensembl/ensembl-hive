=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LSF

=head1 DESCRIPTION

    This is the 'LSF' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2020] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;
use warnings;
use Time::Piece;
use Time::Seconds;

use Bio::EnsEMBL::Hive::Utils ('split_for_bash');

use base ('Bio::EnsEMBL::Hive::Meadow');


our $VERSION = '3.1';       # Semantic version of the Meadow interface:
                            #   change the Major version whenever an incompatible change is introduced,
                            #   change the Minor version whenever the interface is extended, but compatibility is retained.

=head2 name

   Args:       : None
   Description : Determine the LSF cluster_name, if an LSF meadow is available.
   Returntype  : String

=cut

sub name {
    my $re_lsf_names = qr/(IBM Spectrum LSF|Platform LSF|openlava project)/;
    my $re_cluster_name = qr/^My cluster name is\s+(\S+)/;
    my @lsid_out = `lsid 2>/dev/null`;

    my $is_lsf = 0;
    foreach my $lsid_line (@lsid_out) {
        if ($lsid_line =~ $re_lsf_names) {
            $is_lsf = 1;
        } elsif ($lsid_line =~ $re_cluster_name) {
            return $1 if $is_lsf;
        }
    }
}


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


sub count_pending_workers_by_rc_name {
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();
    my @bjobs_out = qx{bjobs -w -J '${jnp}*' 2>/dev/null};  # "-u all" has been removed to ensure one user's PEND processes
                                                          #   do not affect another user helping to run the same pipeline.

#    warn "LSF::count_pending_workers_by_rc_name() running cmd:\n\t$cmd\n";

    my %pending_this_meadow_by_rc_name = ();
    my $total_pending_this_meadow = 0;

    foreach my $line (@bjobs_out) {
        if ($line=~/PEND/) {
            if($line=~/\b\Q$jnp\E(\S+)\-\d+(\[\d+\])?\b/) {
                $pending_this_meadow_by_rc_name{$1}++;
                $total_pending_this_meadow++;
            }
        }
    }

    return (\%pending_this_meadow_by_rc_name, $total_pending_this_meadow);
}


sub count_running_workers {
    my $self                        = shift @_;
    my $meadow_users_of_interest    = shift @_ || [ 'all' ];

    my $jnp = $self->job_name_prefix();

    my $total_running_worker_count = 0;

    foreach my $meadow_user (@$meadow_users_of_interest) {
        my @bjobs_out = qx{bjobs -w -J '${jnp}*' -u $meadow_user 2>/dev/null};

#        warn "LSF::count_running_workers() running cmd:\n\t$cmd\n";

        my $meadow_user_worker_count = scalar(grep {/RUN/} @bjobs_out);

        $total_running_worker_count += $meadow_user_worker_count;
    }

    return $total_running_worker_count;
}


sub status_of_all_our_workers { # returns a hashref
    my $self                        = shift @_;
    my $meadow_users_of_interest    = shift @_ || [ 'all' ];

    my $jnp = $self->job_name_prefix();

    my %status_hash = ();

    foreach my $meadow_user (@$meadow_users_of_interest) {
        my $cmd = "bjobs -w -J '${jnp}*' -u $meadow_user 2>/dev/null";

#        warn "LSF::status_of_all_our_workers() running cmd:\n\t$cmd\n";

        foreach my $line (`$cmd`) {
            my ($group_pid, $user, $status, $queue, $submission_host, $running_host, $job_name) = split(/\s+/, $line);

            next if(($group_pid eq 'JOBID') or ($status eq 'DONE') or ($status eq 'EXIT'));

            my $worker_pid = $group_pid;
            if($job_name=~/(\[\d+\])$/ and $worker_pid!~/\[\d+\]$/) {   # account for the difference in LSF 9.1.1.1 vs LSF 9.1.2.0  bjobs' output
                $worker_pid .= $1;
            }
            $status_hash{$worker_pid} = $status;
        }
    }

    return \%status_hash;
}


sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $this_user = $ENV{'USER'};
    my $cmd = qq{bjobs -u $this_user $wpid 2>&1};

    my @bjobs_out = qx/$cmd/;
#    warn "LSF::check_worker_is_alive_and_mine() running cmd:\n\t$cmd\n";

    my $is_alive_and_mine = 0;
    foreach my $bjobs_line (@bjobs_out) {
        unless ($bjobs_line =~ /JOBID|DONE|EXIT/) { # *SUSP, UNKWN, and ZOMBI are "alive" for the purposes of this call
                                                    # which is typically used to see if the process can be killed.
                                                    # Can't search for line containing the job id, since it may be
                                                    # formatted differently in bjob output than in $worker->process_id()
                                                    # (e.g. for array jobs), so we exclude the header by excluding "JOBID"
            $is_alive_and_mine = 1;
        }
    }
    return $is_alive_and_mine;
}


sub kill_worker {
    my ($self, $worker, $fast) = @_;

    if ($fast) {
        system('bkill', '-r', $worker->process_id());
    } else {
        system('bkill', $worker->process_id());
    }
}


sub _convert_to_datetime {      # a private subroutine that can recover missing year from an incomplete date and then transforms it into SQL's datetime for storage
    my ($weekday, $yearless, $real_year) = @_;

    if($real_year) {
        my $datetime = Time::Piece->strptime("$yearless $real_year", '%b %d %T %Y');
        return $datetime->date.' '.$datetime->hms;
    } else {
        my $curr_year = Time::Piece->new->year();

        my $years_back = 0;
        while ($years_back < 28) {  # The Gregorian calendar repeats every 28 years
            my $candidate_year = $curr_year - $years_back;
            my $datetime = Time::Piece->strptime("$yearless $candidate_year", '%b %d %T %Y');
            if($datetime->wdayname eq $weekday) {
                return $datetime->date.' '.$datetime->hms;
            }
            $years_back++;
        }
    }

    return; # could not guess the year
}


sub parse_report_source_line {
    my ($self, $bacct_source_line) = @_;

    warn "LSF::parse_report_source_line( \"$bacct_source_line\" )\n";

    my %status_2_cod = (
        'TERM_MEMLIMIT'     => 'MEMLIMIT',
        'TERM_RUNLIMIT'     => 'RUNLIMIT',
        'TERM_OWNER'        => 'KILLED_BY_USER',    # bkill     (wait until it dies)
        'TERM_FORCE_OWNER'  => 'KILLED_BY_USER',    # bkill -r  (quick remove)
    );

    my %units_2_megs = (
        'K' => 1.0/1024,
        'M' => 1,
        'G' => 1024,
        'T' => 1024*1024,
    );

    local $/ = "------------------------------------------------------------------------------\n\n";
    open(my $bacct_fh, $bacct_source_line);
    my $record = <$bacct_fh>; # skip the header

    my %report_entry = ();

    for my $record (<$bacct_fh>) {
        chomp $record;

        # warn "RECORD:\n$record";

        my @lines = split(/\n/, $record);
        if( my ($process_id) = $lines[0]=~/^Job <(\d+(?:\[\d+\])?)>/) {

            my ($exit_status, $exception_status) = ('' x 2);
            my ($when_died, $cause_of_death);
            my (@keys, @values);
            my $line_has_key_values = 0;
            foreach (@lines) {
                if( /^(\w+)\s+(\w+\s+\d+\s+\d+:\d+:\d+)(?:\s+(\d{4}))?:\s+Completed\s<(\w+)>(?:\.|;\s+(\w+))/ ) {
                    $when_died      = _convert_to_datetime($1, $2, $3);
                    $cause_of_death = $5 && $status_2_cod{$5};
                    $exit_status = $4 . ($5 ? "/$5" : '');
                }
                elsif(/^\s*EXCEPTION STATUS:\s*(.*?)\s*$/) {
                    $exception_status = $1;
                    $exception_status =~s/\s+/;/g;
                }
                elsif(/^\s*CPU_T/) {
                    @keys = split(/\s+/, ' '.$_);
                    $line_has_key_values = 1;
                }
                elsif($line_has_key_values) {
                    @values = split(/\s+/, ' '.$_);
                    $line_has_key_values = 0;
                }
            }

            my %usage;  @usage{@keys} = @values;

            #warn join(', ', map {sprintf('%s=%s', $_, $usage{$_})} (sort keys %usage)), "\n";

            my ($mem_in_units, $mem_unit)   = $usage{'MEM'}  =~ /^([\d\.]+)([KMGT])$/;
            my ($swap_in_units, $swap_unit) = $usage{'SWAP'} =~ /^([\d\.]+)([KMGT])$/;

            $report_entry{ $process_id } = {
                    # entries for 'worker' table:
                'when_died'         => $when_died,
                'cause_of_death'    => $cause_of_death,

                    # entries for 'worker_resource_usage' table:
                'exit_status'       => $exit_status,
                'exception_status'  => $exception_status,
                'mem_megs'          => $mem_in_units  * $units_2_megs{$mem_unit},
                'swap_megs'         => $swap_in_units * $units_2_megs{$swap_unit},
                'pending_sec'       => $usage{'WAIT'},
                'cpu_sec'           => $usage{'CPU_T'},
                'lifespan_sec'      => $usage{'TURNAROUND'},
            };
        }
    }
    close $bacct_fh;
    my $exit = $? >> 8;
    die "Could not read from '$bacct_source_line'. Received the error $exit\n" if $exit;

    return \%report_entry;
}


sub get_report_entries_for_process_ids {
    my $self = shift @_;    # make sure we get if off the way before splicing

    my %combined_report_entries = ();

    unless ($self->config_get('AccountingDisabled')) {
        while (my $pid_batch = join(' ', map { "'$_'" } splice(@_, 0, 20))) {  # can't fit too many pids on one shell cmdline
            my $cmd = "bacct -l $pid_batch |";

#           warn "LSF::get_report_entries_for_process_ids() running cmd:\n\t$cmd\n";

            my $batch_of_report_entries = $self->parse_report_source_line( $cmd );

            %combined_report_entries = (%combined_report_entries, %$batch_of_report_entries);
        }
    }

    return \%combined_report_entries;
}


sub get_report_entries_for_time_interval {
    my ($self, $from_time, $to_time, $username) = @_;

    my $batch_of_report_entries = {};

    unless ($self->config_get('AccountingDisabled')) {
        my $from_timepiece = Time::Piece->strptime($from_time, '%Y-%m-%d %H:%M:%S');
        $from_time = $from_timepiece->strftime('%Y/%m/%d/%H:%M');

        my $to_timepiece = Time::Piece->strptime($to_time, '%Y-%m-%d %H:%M:%S') + 2*ONE_MINUTE;
        $to_time = $to_timepiece->strftime('%Y/%m/%d/%H:%M');

        my $cmd = "bacct -l -C $from_time,$to_time ".($username ? "-u $username" : '') . ' |';

#        warn "LSF::get_report_entries_for_time_interval() running cmd:\n\t$cmd\n";

        $batch_of_report_entries = $self->parse_report_source_line( $cmd );
    }

    return $batch_of_report_entries;
}


sub submit_workers {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my $job_array_common_name               = $self->job_array_common_name($rc_name, $iteration);
    my $job_array_name_with_indices         = $job_array_common_name . (($required_worker_count > 1) ? "[1-${required_worker_count}]" : '');
    my $meadow_specific_submission_cmd_args = $self->config_get('SubmissionOptions');

    my ($submit_stdout_file, $submit_stderr_file);

    if($submit_log_subdir) {
        $submit_stdout_file = $submit_log_subdir . "/log_${rc_name}_%J_%I.out";
        $submit_stderr_file = $submit_log_subdir . "/log_${rc_name}_%J_%I.err";
    } else {
        $submit_stdout_file = '/dev/null';
        $submit_stderr_file = '/dev/null';
    }

    $ENV{'LSB_STDOUT_DIRECT'} = 'y';  # unbuffer the output of the bsub command
    delete $ENV{'LSB_JOBID'};
    delete $ENV{'LSB_JOBINDEX'};

    my @cmd = ('bsub',
        '-o', $submit_stdout_file,
        '-e', $submit_stderr_file,
        '-J', $job_array_name_with_indices,
        split_for_bash($rc_specific_submission_cmd_args),
        split_for_bash($meadow_specific_submission_cmd_args),
        $worker_cmd
    );

    print "Executing [ ".$self->signature." ] \t\t".join(' ', @cmd)."\n";

    system( @cmd ) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax
}

1;
