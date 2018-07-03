=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LSF

=head1 DESCRIPTION

    This is the 'LSF' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2018] EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Utils ('split_for_bash');

use base ('Bio::EnsEMBL::Hive::Meadow');


our $VERSION = '1.0';       # Semantic version of the Meadow interface:
                            #   change the Major version whenever an incompatible change is introduced,
                            #   change the Minor version whenever the interface is extended, but compatibility is retained.

=head2 name

   Args:       : None
   Description : Determine the LSF cluster_name, if an LSF meadow is available.
   Returntype  : String

=cut

sub name {
    my $mcni = 'My cluster name is';
    my @lsid_out = `lsid 2>/dev/null`;

    foreach my $lsid_line (@lsid_out) {
        if ($lsid_line =~ /^$mcni\s+(\S+)/) {
            return $1;
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
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();
    my @bjobs_out = qx{bjobs -w -J '${jnp}*' -u all 2>/dev/null};

#    warn "LSF::count_running_workers() running cmd:\n\t$cmd\n";

    my $run_count = scalar(grep {/RUN/} @bjobs_out);

    return $run_count;
}


sub status_of_all_our_workers { # returns a hashref
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();
    my $cmd = "bjobs -w -J '${jnp}*' -u all 2>/dev/null";

#    warn "LSF::status_of_all_our_workers() running cmd:\n\t$cmd\n";

    my %status_hash = ();
    foreach my $line (`$cmd`) {
        my ($group_pid, $user, $status, $queue, $submission_host, $running_host, $job_name) = split(/\s+/, $line);

        next if(($group_pid eq 'JOBID') or ($status eq 'DONE') or ($status eq 'EXIT'));

        my $worker_pid = $group_pid;
        if($job_name=~/(\[\d+\])$/ and $worker_pid!~/\[\d+\]$/) {   # account for the difference in LSF 9.1.1.1 vs LSF 9.1.2.0  bjobs' output
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
    my $worker = pop @_;

    my $cmd = 'bkill '.$worker->process_id();

#    warn "LSF::kill_worker() running cmd:\n\t$cmd\n";

    system($cmd);
}


sub find_out_causes {
    my $self = shift @_;

    my %lsf_2_hive = (
        'TERM_MEMLIMIT'     => 'MEMLIMIT',
        'TERM_RUNLIMIT'     => 'RUNLIMIT',
        'TERM_OWNER'        => 'KILLED_BY_USER',    # bkill     (wait until it dies)
        'TERM_FORCE_OWNER'  => 'KILLED_BY_USER',    # bkill -r  (quick remove)
    );

    my %cod = ();

    while (my $pid_batch = join(' ', map { "'$_'" } splice(@_, 0, 20))) {  # can't fit too many pids on one shell cmdline
        my $cmd = "bacct -l $pid_batch";

#        warn "LSF::find_out_causes() running cmd:\n\t$cmd\n";

        foreach my $section (split(/\-{10,}\s+/, `$cmd`)) {
            if($section=~/^Job <(\d+(?:\[\d+\])?)>.+(TERM_\w+): job killed/is) {
                $cod{$1} = $lsf_2_hive{$2};
            }
        }
    }

    return \%cod;
}


sub submit_workers {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_stdout_file, $submit_stderr_file) = @_;

    my $job_name                            = $self->generate_job_name($required_worker_count, $iteration, $rc_name);
    my $meadow_specific_submission_cmd_args = $self->config_get('SubmissionOptions');

    $submit_stdout_file ||= '/dev/null';    # a value is required
    $submit_stderr_file ||= '/dev/null';    # a value is required

    $ENV{'LSB_STDOUT_DIRECT'} = 'y';  # unbuffer the output of the bsub command

    my @cmd = ('bsub',
        '-o', $submit_stdout_file,
        '-e', $submit_stderr_file,
        '-J', $job_name,
        split_for_bash($rc_specific_submission_cmd_args),
        split_for_bash($meadow_specific_submission_cmd_args),
        $worker_cmd
    );

    warn "LSF::submit_workers() running cmd:\n\t".join(' ', @cmd)."\n";

    system( @cmd ) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax
}

1;
