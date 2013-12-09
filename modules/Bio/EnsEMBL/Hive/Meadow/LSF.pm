=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::LSF

=head1 DESCRIPTION

    This is the 'LSF' implementation of Meadow

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::Meadow::LSF;

use strict;

use base ('Bio::EnsEMBL::Hive::Meadow');


sub name {  # also called to check for availability; assume LSF is available if LSF cluster_name can be established
    my $mcni = 'My cluster name is';
    my $cmd = "lsid 2>/dev/null | grep '$mcni'";

#    warn "LSF::name() running cmd:\n\t$cmd\n";

    if(my $name = `$cmd`) {
        $name=~/^$mcni\s+(\S+)/;
        return $1;
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
    my $cmd = "bjobs -w -J '${jnp}*' -u all 2>/dev/null | grep PEND";

#    warn "LSF::count_pending_workers_by_rc_name() running cmd:\n\t$cmd\n";

    my %pending_this_meadow_by_rc_name = ();
    my $total_pending_this_meadow = 0;

    foreach my $line (qx/$cmd/) {
        if($line=~/\b\Q$jnp\E(\S+)\-\d+(\[\d+\])?\b/) {
            $pending_this_meadow_by_rc_name{$1}++;
            $total_pending_this_meadow++;
        }
    }

    return (\%pending_this_meadow_by_rc_name, $total_pending_this_meadow);
}


sub count_running_workers {
    my ($self) = @_;

    my $jnp = $self->job_name_prefix();
    my $cmd = "bjobs -w -J '${jnp}*' -u all 2>/dev/null | grep RUN | wc -l";

#    warn "LSF::count_running_workers() running cmd:\n\t$cmd\n";

    my $run_count = qx/$cmd/;
    chomp($run_count);

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
        if($job_name=~/(\[\d+\])/) {
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
    my $cmd = qq{bjobs $wpid -u $this_user 2>&1 | grep -v 'not found' | grep -v JOBID | grep -v EXIT};

#    warn "LSF::check_worker_is_alive_and_mine() running cmd:\n\t$cmd\n";

    my $is_alive_and_mine = qx/$cmd/;
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
        'TERM_MEMLIMIT' => 'MEMLIMIT',
        'TERM_RUNLIMIT' => 'RUNLIMIT',
        'TERM_OWNER'    => 'KILLED_BY_USER',
    );

    my %cod = ();

    while (my $pid_batch = join(' ', map { "'$_'" } splice(@_, 0, 20))) {  # can't fit too many pids on one shell cmdline
        my $cmd = "bacct -l $pid_batch";

#        warn "LSF::find_out_causes() running cmd:\n\t$cmd\n";

        foreach my $section (split(/\-{10,}\s+/, `$cmd`)) {
            if($section=~/^Job <(\d+(?:\[\d+\])?)>.+(TERM_MEMLIMIT|TERM_RUNLIMIT|TERM_OWNER): job killed/is) {
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

    my $cmd = qq{bsub -o $submit_stdout_file -e $submit_stderr_file -J "${job_name}" $rc_specific_submission_cmd_args $meadow_specific_submission_cmd_args $worker_cmd};

    warn "LSF::submit_workers() running cmd:\n\t$cmd\n";

    system($cmd) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax
}

1;
