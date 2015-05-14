=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Queen

=head1 DESCRIPTION

    The Queen of the Hive based job control system is responsible to 'birthing' the
    correct number of workers of the right type so that they can find jobs to do.
    It will also free up jobs of Workers that died unexpectantly so that other workers
    can claim them to do.

    Hive based processing is a concept based on a more controlled version
    of an autonomous agent type system.  Each worker is not told what to do
    (like a centralized control system - like the current pipeline system)
    but rather queries a central database for jobs (give me jobs).

    Each worker is linked to an analysis_id, registers its self on creation
    into the Hive, creates a RunnableDB instance of the Analysis->module,
    gets $analysis->stats->batch_size jobs from the job table, does its work,
    creates the next layer of job entries by interfacing to
    the DataflowRuleAdaptor to determine the analyses it needs to pass its
    output data to and creates jobs on the next analysis database.
    It repeats this cycle until it has lived its lifetime or until there are no
    more jobs left.
    The lifetime limit is just a safety limit to prevent these from 'infecting'
    a system.

    The Queens job is to simply birth Workers of the correct analysis_id to get the
    work down.  The only other thing the Queen does is free up jobs that were
    claimed by Workers that died unexpectantly so that other workers can take
    over the work.

    The Beekeeper is in charge of interfacing between the Queen and a compute resource
    or 'compute farm'.  Its job is to query Queens if they need any workers and to
    send the requested number of workers to open machines via the runWorker.pl script.
    It is also responsible for interfacing with the Queen to identify worker which died
    unexpectantly.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=head1 APPENDIX

    The rest of the documentation details each of the object methods. 
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Queen;

use strict;
use warnings;
use File::Path 'make_path';
use List::Util qw(max);

use Bio::EnsEMBL::Hive::Utils ('destringify', 'dir_revhash');  # NB: needed by invisible code
use Bio::EnsEMBL::Hive::Role;
use Bio::EnsEMBL::Hive::Scheduler;
use Bio::EnsEMBL::Hive::Worker;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'worker';
}


sub default_insertion_method {
    return 'INSERT';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Worker';
}


############################
#
# PUBLIC API
#
############################


=head2 create_new_worker

  Description: Creates an entry in the worker table,
               populates some non-storable attributes
               and returns a Worker object based on that insert.
               This guarantees that each worker registered in this Queen's hive is properly registered.
  Returntype : Bio::EnsEMBL::Hive::Worker
  Caller     : runWorker.pl

=cut

sub create_new_worker {
    my $self    = shift @_;
    my %flags   = @_;

    my ($meadow_type, $meadow_name, $process_id, $meadow_host, $meadow_user, $resource_class_id, $resource_class_name,
        $no_write, $debug, $worker_log_dir, $hive_log_dir, $job_limit, $life_span, $no_cleanup, $retry_throwing_jobs, $can_respecialize)
     = @flags{qw(-meadow_type -meadow_name -process_id -meadow_host -meadow_user -resource_class_id -resource_class_name
            -no_write -debug -worker_log_dir -hive_log_dir -job_limit -life_span -no_cleanup -retry_throwing_jobs -can_respecialize)};

    foreach my $prev_worker_incarnation (@{ $self->fetch_all( "status!='DEAD' AND meadow_type='$meadow_type' AND meadow_name='$meadow_name' AND process_id='$process_id'" ) }) {
            # so far 'RELOCATED events' has been detected on LSF 9.0 in response to sending signal #99 or #100
            # Since I don't know how to avoid them, I am trying to register them when they happen.
            # The following snippet buries the previous incarnation of the Worker before starting a new one.
            #
            # FIXME: if GarabageCollector (beekeeper -dead) gets to these processes first, it will register them as DEAD/UNKNOWN.
            #       LSF 9.0 does not report "rescheduling" events in the output of 'bacct', but does mention them in 'bhist'.
            #       So parsing 'bhist' output would probably yield the most accurate & confident registration of these events.
        $prev_worker_incarnation->cause_of_death( 'RELOCATED' );
        $self->register_worker_death( $prev_worker_incarnation );
    }

    my $resource_class;

    if( defined($resource_class_name) ) {
        $resource_class = $self->db->get_ResourceClassAdaptor->fetch_by_name($resource_class_name)
            or die "resource_class with name='$resource_class_name' could not be fetched from the database";
    } elsif( defined($resource_class_id) ) {
        $resource_class = $self->db->get_ResourceClassAdaptor->fetch_by_dbID($resource_class_id)
            or die "resource_class with dbID='$resource_class_id' could not be fetched from the database";
    }

    my $worker = Bio::EnsEMBL::Hive::Worker->new(
        'meadow_type'       => $meadow_type,
        'meadow_name'       => $meadow_name,
        'meadow_host'       => $meadow_host,
        'meadow_user'       => $meadow_user,
        'process_id'        => $process_id,
        'resource_class'    => $resource_class,
    );
    $self->store( $worker );
    my $worker_id = $worker->dbID;

    $worker = $self->fetch_by_dbID( $worker_id )    # refresh the object to get the fields initialized at SQL level (timestamps in this case)
        or die "Could not fetch worker with dbID=$worker_id";

    if($hive_log_dir or $worker_log_dir) {
        my $dir_revhash = dir_revhash($worker_id);
        $worker_log_dir ||= $hive_log_dir .'/'. ($dir_revhash ? "$dir_revhash/" : '') .'worker_id_'.$worker_id;

        eval {
            make_path( $worker_log_dir );
            1;
        } or die "Could not create '$worker_log_dir' directory : $@";

        $worker->log_dir( $worker_log_dir );
        $self->update_log_dir( $worker );   # autoloaded
    }

    $worker->init;

    if(defined($job_limit)) {
      $worker->job_limiter($job_limit);
      $worker->life_span(0);
    }

    $worker->life_span($life_span * 60)                 if($life_span);

    $worker->execute_writes(0)                          if($no_write);

    $worker->perform_cleanup(0)                         if($no_cleanup);

    $worker->debug($debug)                              if($debug);

    $worker->retry_throwing_jobs($retry_throwing_jobs)  if(defined $retry_throwing_jobs);

    $worker->can_respecialize($can_respecialize)        if(defined $can_respecialize);

    return $worker;
}


=head2 specialize_worker

  Description: If analysis_id or logic_name is specified it will try to specialize the Worker into this analysis.
               If not specified the Queen will analyze the hive and pick the most suitable analysis.
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub specialize_worker {
    my $self    = shift @_;
    my $worker  = shift @_;
    my $flags   = shift @_;

    my ($analyses_pattern, $job_id, $force)
     = @$flags{qw(-analyses_pattern -job_id -force)};

    if( $analyses_pattern and $job_id ) {
        die "At most one of the options {-analyses_pattern, -job_id} can be set to pre-specialize a Worker";
    }

    my $analysis;

    if( $job_id ) {

        warn "resetting and fetching job for job_id '$job_id'\n";

        my $job_adaptor = $self->db->get_AnalysisJobAdaptor;

        my $job = $job_adaptor->fetch_by_dbID( $job_id )
            or die "Could not fetch job with dbID='$job_id'";
        my $job_status = $job->status();

        if($job_status =~/(CLAIMED|PRE_CLEANUP|FETCH_INPUT|RUN|WRITE_OUTPUT|POST_CLEANUP)/ ) {
            die "Job with dbID='$job_id' is already in progress, cannot run";   # FIXME: try GC first, then complain
        } elsif($job_status =~/(DONE|SEMAPHORED)/ and !$force) {
            die "Job with dbID='$job_id' is $job_status, please use -force 1 to override";
        }

        if(($job_status eq 'DONE') and $job->semaphored_job_id) {
            warn "Increasing the semaphore count of the dependent job";
            $job_adaptor->increase_semaphore_count_for_jobid( $job->semaphored_job_id );
        }

        $analysis = $job->analysis;

    } else {

        $analyses_pattern //= '%';  # for printing
        my $analyses_matching_pattern   = Bio::EnsEMBL::Hive::Analysis->collection()->find_all_by_pattern( $analyses_pattern );

            # refresh the stats of matching analyses before re-specialization:
        foreach my $analysis ( @$analyses_matching_pattern ) {
            $analysis->stats->refresh();
        }

        $analysis = Bio::EnsEMBL::Hive::Scheduler::suggest_analysis_to_specialize_a_worker($worker, $analyses_matching_pattern, $analyses_pattern);

        unless( ref($analysis) ) {

            $worker->cause_of_death('NO_ROLE');

            my $msg = $analysis // "No analysis suitable for the worker was found";
            die "$msg\n";
        }
    }

    my $new_role = Bio::EnsEMBL::Hive::Role->new(
        'worker'        => $worker,
        'analysis'      => $analysis,
    );
    $self->db->get_RoleAdaptor->store( $new_role );
    $worker->current_role( $new_role );

    my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

    if($job_id) {
        my $role_id = $new_role->dbID;
        if( my $job = $self->db->get_AnalysisJobAdaptor->reset_or_grab_job_by_dbID($job_id, $role_id) ) {

            $worker->special_batch( [ $job ] );
        } else {
            die "Could not claim job with dbID='$job_id' for Role with dbID='$role_id'";
        }

    } else {    # Note: special batch Workers should avoid flipping the status to 'WORKING' in case the analysis is still 'BLOCKED'

        $analysis_stats_adaptor->update_status($analysis->dbID, 'WORKING');
    }

        # The following increment used to be done only when no specific task was given to the worker,
        # thereby excluding such "special task" workers from being counted in num_running_workers.
        #
        # However this may be tricky to emulate by triggers that know nothing about "special tasks",
        # so I am (temporarily?) simplifying the accounting algorithm.
        #
    $analysis_stats_adaptor->increment_a_counter( 'num_running_workers', 1, $analysis->dbID );
}


sub register_worker_death {
    my ($self, $worker, $update_when_checked_in) = @_;

    my $worker_id       = $worker->dbID;
    my $work_done       = $worker->work_done;
    my $cause_of_death  = $worker->cause_of_death || 'UNKNOWN';    # make sure we do not attempt to insert a void
    my $worker_died     = $worker->when_died;

    my $current_role    = $worker->current_role;

    unless( $current_role ) {
        $worker->current_role( $current_role = $self->db->get_RoleAdaptor->fetch_last_unfinished_by_worker_id( $worker_id ) );
    }

    if( $current_role and !$current_role->when_finished() ) {
        # List of cause_of_death:
        # only happen before or after a batch: 'NO_ROLE','NO_WORK','JOB_LIMIT','HIVE_OVERLOAD','LIFESPAN','SEE_MSG'
        # can happen whilst the worker is running a batch: 'CONTAMINATED','RELOCATED','KILLED_BY_USER','MEMLIMIT','RUNLIMIT','SEE_MSG','UNKNOWN'
        my $release_undone_jobs = ($cause_of_death =~ /^(CONTAMINATED|RELOCATED|KILLED_BY_USER|MEMLIMIT|RUNLIMIT|SEE_MSG|UNKNOWN)$/);
        $current_role->worker($worker); # So that release_undone_jobs_from_role() has the correct cause_of_death and work_done
        $current_role->when_finished( $worker_died );
        $self->db->get_RoleAdaptor->finalize_role( $current_role, $release_undone_jobs );
    }

    my $sql = "UPDATE worker SET status='DEAD', work_done='$work_done', cause_of_death='$cause_of_death'"
            . ( $update_when_checked_in ? ', when_checked_in=CURRENT_TIMESTAMP ' : '' )
            . ( $worker_died ? ", when_died='$worker_died'" : ', when_died=CURRENT_TIMESTAMP' )
            . " WHERE worker_id='$worker_id' ";

    $self->dbc->protected_prepare_execute( [ $sql ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $worker, "register_worker_death".$after, 0 ); }
    );
}


sub meadow_type_2_name_2_users_of_running_workers {
    my $self = shift @_;

    return $self->count_all("status!='DEAD'", ['meadow_type', 'meadow_name', 'meadow_user']);
}


sub check_for_dead_workers {    # scans the whole Valley for lost Workers (but ignores unreachable ones)
    my ($self, $valley, $check_buried_in_haste, $bury_unkwn_workers) = @_;

    my $last_few_seconds            = 5;    # FIXME: It is probably a good idea to expose this parameter for easier tuning.

    warn "GarbageCollector:\tChecking for lost Workers...\n";

    my $meadow_type_2_name_2_users      = $self->meadow_type_2_name_2_users_of_running_workers();
    my %signature_and_pid_to_worker_status = ();

    while(my ($meadow_type, $level2) = each %$meadow_type_2_name_2_users) {

        if(my $meadow = $valley->available_meadow_hash->{$meadow_type}) {   # if this Valley supports $meadow_type at all...
            while(my ($meadow_name, $level3) = each %$level2) {

                if($meadow->cached_name eq $meadow_name) {  # and we can reach the same $meadow_name from this Valley...
                    my $meadow_users_of_interest    = [ keys %$level3 ];
                    my $meadow_signature            = $meadow_type.'/'.$meadow_name;

                    $signature_and_pid_to_worker_status{$meadow_signature} ||= $meadow->status_of_all_our_workers( $meadow_users_of_interest );
                }
            }
        }
    }

    my $queen_overdue_workers       = $self->fetch_overdue_workers( $last_few_seconds );    # check the workers we have not seen active during the $last_few_seconds
    warn "GarbageCollector:\t[Queen:] out of ".scalar(@$queen_overdue_workers)." Workers that haven't checked in during the last $last_few_seconds seconds...\n";

    my $update_when_seen_sql = "UPDATE worker SET when_seen=CURRENT_TIMESTAMP WHERE worker_id=?";
    my $update_when_seen_sth;

    my %meadow_status_counts        = ();
    my %mt_and_pid_to_lost_worker   = ();
    foreach my $worker (@$queen_overdue_workers) {

        my $meadow_signature    = $worker->meadow_type.'/'.$worker->meadow_name;
        if(my $pid_to_worker_status = $signature_and_pid_to_worker_status{$meadow_signature}) {   # the whole Meadow subhash is either present or the Meadow is unreachable

            my $meadow_type = $worker->meadow_type;
            my $process_id  = $worker->process_id;
            my $status = $pid_to_worker_status->{$process_id};

            if($bury_unkwn_workers and ($status eq 'UNKWN')) {
                if( my $meadow = $valley->find_available_meadow_responsible_for_worker( $worker ) ) {
                    if($meadow->can('kill_worker')) {
                        if($worker->meadow_user eq $ENV{'USER'}) {  # if I'm actually allowed to kill the worker...
                            warn "GarbageCollector:\tKilling/forgetting the UNKWN worker by process_id $process_id";

                            $meadow->kill_worker($worker, 1);
                            $status = ''; # make it look like LOST
                        }
                    }
                }
            }

            if($status) {  # can be RUN|PEND|xSUSP
                $meadow_status_counts{$meadow_signature}{$status}++;

                    # only prepare once at most:
                $update_when_seen_sth ||= $self->prepare( $update_when_seen_sql );

                $update_when_seen_sth->execute( $worker->dbID );
            } else {
                $meadow_status_counts{$meadow_signature}{'LOST'}++;

                $mt_and_pid_to_lost_worker{$meadow_type}{$process_id} = $worker;
            }
        } else {
            $meadow_status_counts{$meadow_signature}{'UNREACHABLE'}++;   # Worker is unreachable from this Valley
        }
    }

    $update_when_seen_sth->finish() if $update_when_seen_sth;

        # print a quick summary report:
    while(my ($meadow_signature, $status_count) = each %meadow_status_counts) {
        warn "GarbageCollector:\t[$meadow_signature Meadow:]\t".join(', ', map { "$_:$status_count->{$_}" } keys %$status_count )."\n\n";
    }

    while(my ($meadow_type, $pid_to_lost_worker) = each %mt_and_pid_to_lost_worker) {
        my $this_meadow = $valley->available_meadow_hash->{$meadow_type};

        if(my $lost_this_meadow = scalar(keys %$pid_to_lost_worker) ) {
            warn "GarbageCollector:\tDiscovered $lost_this_meadow lost $meadow_type Workers\n";

            my $report_entries = {};

            if($this_meadow->can('find_out_causes')) {
                die "Your Meadow::$meadow_type driver now has to support get_report_entries_for_process_ids() method instead of find_out_causes(). Please update it.\n";

            } elsif($this_meadow->can('get_report_entries_for_process_ids')) {
                $report_entries = $this_meadow->get_report_entries_for_process_ids( keys %$pid_to_lost_worker );
                my $lost_with_known_cod = scalar( grep { $_->{'cause_of_death'} } values %$report_entries);
                warn "GarbageCollector:\tFound why $lost_with_known_cod of $meadow_type Workers died\n";
            } else {
                warn "GarbageCollector:\t$meadow_type meadow does not support post-mortem examination\n";
            }

            warn "GarbageCollector:\tReleasing the jobs\n";
            while(my ($process_id, $worker) = each %$pid_to_lost_worker) {
                $worker->when_died(         $report_entries->{$process_id}{'when_died'} );
                $worker->cause_of_death(    $report_entries->{$process_id}{'cause_of_death'} );
                $self->register_worker_death( $worker );
            }

            if( %$report_entries ) {    # use the opportunity to also store resource usage of the buried workers:
                my $processid_2_workerid = { map { $_ => $pid_to_lost_worker->{$_}->dbID } keys %$pid_to_lost_worker };
                $self->store_resource_usage( $report_entries, $processid_2_workerid );
            }
        }
    }

        # the following bit is completely Meadow-agnostic and only restores database integrity:
    if($check_buried_in_haste) {
        warn "GarbageCollector:\tChecking for Workers/Roles buried in haste...\n";
        my $buried_in_haste_list = $self->db->get_RoleAdaptor->fetch_all_finished_roles_with_unfinished_jobs();
        if(my $bih_number = scalar(@$buried_in_haste_list)) {
            warn "GarbageCollector:\tfound $bih_number jobs, reclaiming.\n\n";
            if($bih_number) {
                my $job_adaptor = $self->db->get_AnalysisJobAdaptor;
                foreach my $role (@$buried_in_haste_list) {
                    $job_adaptor->release_undone_jobs_from_role( $role );
                }
            }
        } else {
            warn "GarbageCollector:\tfound none\n";
        }
    }
}


    # a new version that both checks in and updates the status
sub check_in_worker {
    my ($self, $worker) = @_;

    my $sql = "UPDATE worker SET when_checked_in=CURRENT_TIMESTAMP, status='".$worker->status."', work_done='".$worker->work_done."' WHERE worker_id='".$worker->dbID."'";

    $self->dbc->protected_prepare_execute( [ $sql ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_worker_message( $worker, "check_in_worker".$after, 0 ); }
    );
}


=head2 reset_job_by_dbID_and_sync

  Arg [1]: int $job_id
  Example: 
    my $job = $queen->reset_job_by_dbID_and_sync($job_id);
  Description: 
    For the specified job_id it will fetch just that job, 
    reset it completely as if it has never run, and return it.  
    Specifying a specific job bypasses the safety checks, 
    thus multiple workers could be running the 
    same job simultaneously (use only for debugging).
  Returntype : none
  Exceptions :
  Caller     : beekeeper.pl

=cut

sub reset_job_by_dbID_and_sync {
    my ($self, $job_id) = @_;

    my $job     = $self->db->get_AnalysisJobAdaptor->reset_or_grab_job_by_dbID($job_id);

    my $stats   = $job->analysis->stats;

    $self->synchronize_AnalysisStats($stats);
}


######################################
#
# Public API interface for beekeeper
#
######################################


    # Note: asking for Queen->fetch_overdue_workers(0) essentially means
    #       "fetch all workers known to the Queen not to be officially dead"
    #
sub fetch_overdue_workers {
    my ($self,$overdue_secs) = @_;

    $overdue_secs = 3600 unless(defined($overdue_secs));

    my $constraint = "status!='DEAD' AND ".{
            'mysql'     =>  "(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(when_checked_in)) > $overdue_secs",
            'sqlite'    =>  "(strftime('%s','now')-strftime('%s',when_checked_in)) > $overdue_secs",
            'pgsql'     =>  "EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - when_checked_in) > $overdue_secs",
        }->{ $self->dbc->driver };

    return $self->fetch_all( $constraint );
}


=head2 synchronize_hive

  Arg [1]    : $list_of_analyses
  Example    : $queen->synchronize_hive( [ $analysis_A, $analysis_B ] );
  Description: Runs through all analyses in the given list and synchronizes
              the analysis_stats summary with the states in the job and worker tables.
              Then follows by checking all the blocking rules and blocks/unblocks analyses as needed.
  Exceptions : none
  Caller     : general

=cut

sub synchronize_hive {
    my ($self, $list_of_analyses) = @_;

    my $start_time = time();

    print STDERR "\nSynchronizing the hive (".scalar(@$list_of_analyses)." analyses this time):\n";
    foreach my $analysis (@$list_of_analyses) {
        $self->synchronize_AnalysisStats($analysis->stats);
        print STDERR ( ($analysis->stats()->status eq 'BLOCKED') ? 'x' : 'o');
    }
    print STDERR "\n";

    print STDERR ''.((time() - $start_time))." seconds to synchronize_hive\n\n";
}


=head2 safe_synchronize_AnalysisStats

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    : $self->safe_synchronize_AnalysisStats($stats);
  Description: Prewrapper around synchronize_AnalysisStats that does
               checks and grabs sync_lock before proceeding with sync.
               Used by distributed worker sync system to avoid contention.
               Returns 1 on success and 0 if the lock could not have been obtained,
               and so no sync was attempted.
  Returntype : boolean
  Caller     : general

=cut

sub safe_synchronize_AnalysisStats {
    my ($self, $stats) = @_;

    $stats->refresh();

    my $max_refresh_attempts = 5;
    while($stats->sync_lock and $max_refresh_attempts--) {   # another Worker/Beekeeper is synching this analysis right now
            # ToDo: it would be nice to report the detected collision
        sleep(1);
        $stats->refresh();  # just try to avoid collision
    }

    unless( ($stats->status eq 'DONE')
         or ( ($stats->status eq 'WORKING') and defined($stats->seconds_since_when_updated) and ($stats->seconds_since_when_updated < 3*60) ) ) {

        my $sql = "UPDATE analysis_stats SET status='SYNCHING', sync_lock=1 ".
                  "WHERE sync_lock=0 and analysis_id=" . $stats->analysis_id;

        my $row_count = $self->dbc->do($sql);   # try to claim the sync_lock

        if( $row_count == 1 ) {     # if we managed to obtain the lock, let's go and perform the sync:
            $self->synchronize_AnalysisStats($stats);   
            return 1;
        } # otherwise assume it's locked and just return un-updated
    }

    return 0;
}


=head2 synchronize_AnalysisStats

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    : $self->synchronize_AnalysisStats( $stats );
  Description: Queries the job and worker tables to get summary counts
               and rebuilds the AnalysisStats object.
               Then updates the analysis_stats table with the new summary info.
  Exceptions : none
  Caller     : general

=cut

sub synchronize_AnalysisStats {
    my ($self, $stats) = @_;

    if( $stats and $stats->analysis_id ) {

        $stats->refresh(); ## Need to get the new hive_capacity for dynamic analyses

        my $job_counts = $self->db->hive_use_triggers() ? undef : $self->db->get_AnalysisJobAdaptor->fetch_job_counts_hashed_by_status( $stats->analysis_id );

        $stats->recalculate_from_job_counts( $job_counts );

        # $stats->sync_lock(0); ## do we perhaps need it here?
        $stats->update;  #update and release sync_lock
    }
}


=head2 check_nothing_to_run_but_semaphored

  Arg [1]    : $list_of_analyses
  Example    : $self->check_nothing_to_run_but_semaphored( [ $analysis_A, $analysis_B ] );
  Description: Counts the number of immediately runnable jobs in the given analyses.
  Exceptions : none
  Caller     : Scheduler

=cut

sub check_nothing_to_run_but_semaphored {   # make sure it is run after a recent sync
    my ($self, $list_of_analyses) = @_;

    my $only_semaphored_jobs_to_run = 1;
    my $total_semaphored_job_count  = 0;

    foreach my $analysis (@$list_of_analyses) {
        my $stats = $analysis->stats;

        $only_semaphored_jobs_to_run = 0 if( $stats->total_job_count != $stats->done_job_count + $stats->failed_job_count + $stats->semaphored_job_count );
        $total_semaphored_job_count += $stats->semaphored_job_count;
    }

    return ( $total_semaphored_job_count && $only_semaphored_jobs_to_run );
}


=head2 print_status_and_return_reasons_to_exit

  Arg [1]    : $list_of_analyses
  Example    : my $reasons_to_exit = $queen->print_status_and_return_reasons_to_exit( [ $analysis_A, $analysis_B ] );
  Description: Runs through all analyses in the given list, reports failed analyses, computes some totals, prints a combined status line
                and returns a pair of ($failed_analyses_counter, $total_jobs_to_do)
  Exceptions : none
  Caller     : beekeeper.pl

=cut

sub print_status_and_return_reasons_to_exit {
    my ($self, $list_of_analyses) = @_;

    my ($total_done_jobs, $total_failed_jobs, $total_jobs, $cpumsec_to_do) = (0) x 4;
    my $reasons_to_exit = '';

    my $max_logic_name_length = max(map {length($_->logic_name)} @$list_of_analyses);

    foreach my $analysis (sort {$a->dbID <=> $b->dbID} @$list_of_analyses) {
        my $stats               = $analysis->stats;
        my $failed_job_count    = $stats->failed_job_count;

        print $stats->toString($max_logic_name_length) . "\n";

        if( $stats->status eq 'FAILED') {
            my $logic_name    = $analysis->logic_name;
            my $tolerance     = $analysis->failed_job_tolerance;
            $reasons_to_exit .= "### Analysis '$logic_name' has FAILED  (failed Jobs: $failed_job_count, tolerance: $tolerance\%) ###\n";
        }

        $total_done_jobs    += $stats->done_job_count;
        $total_failed_jobs  += $failed_job_count;
        $total_jobs         += $stats->total_job_count;
        $cpumsec_to_do      += $stats->ready_job_count * $stats->avg_msec_per_job;
    }

    my $total_jobs_to_do        = $total_jobs - $total_done_jobs - $total_failed_jobs;         # includes SEMAPHORED, READY, CLAIMED, INPROGRESS
    my $cpuhrs_to_do            = $cpumsec_to_do / (1000.0*60*60);
    my $percentage_completed    = $total_jobs
                                    ? (($total_done_jobs+$total_failed_jobs)*100.0/$total_jobs)
                                    : 0.0;

    printf("total over %d analyses : %6.2f%% complete (< %.2f CPU_hrs) (%d to_do + %d done + %d failed = %d total)\n",
                scalar(@$list_of_analyses), $percentage_completed, $cpuhrs_to_do, $total_jobs_to_do, $total_done_jobs, $total_failed_jobs, $total_jobs);

    unless( $total_jobs_to_do ) {
        $reasons_to_exit .= "### No jobs left to do ###\n";
    }

    return $reasons_to_exit;
}


=head2 register_all_workers_dead

  Example    : $queen->register_all_workers_dead();
  Description: Registers all workers dead
  Exceptions : none
  Caller     : beekeeper.pl

=cut

sub register_all_workers_dead {
    my $self = shift;

    my $all_workers_considered_alive = $self->fetch_all( "status!='DEAD'" );
    foreach my $worker (@{$all_workers_considered_alive}) {
        $self->register_worker_death( $worker );
    }
}


sub interval_workers_with_unknown_usage {
    my $self = shift @_;

    my %meadow_to_interval = ();

    my $sql_times = qq{
        SELECT meadow_type, meadow_name, min(when_born), max(when_died), count(*)
        FROM worker w
        LEFT JOIN worker_resource_usage u USING(worker_id)
        WHERE u.worker_id IS NULL
        GROUP BY meadow_type, meadow_name
    };
    my $sth_times = $self->prepare( $sql_times );
    $sth_times->execute();
    while( my ($meadow_type, $meadow_name, $min_born, $max_died, $workers_count) = $sth_times->fetchrow_array() ) {
        $meadow_to_interval{$meadow_type}{$meadow_name} = {
            'min_born'      => $min_born,
            'max_died'      => $max_died,
            'workers_count' => $workers_count,
        };
    }
    $sth_times->finish();

    return \%meadow_to_interval;
}


sub store_resource_usage {
    my ($self, $report_entries, $processid_2_workerid) = @_;

    # FIXME: An UPSERT would be better here, but it is only promised in PostgreSQL starting from 9.5, which is not officially out yet.

    my $sql_delete = 'DELETE FROM worker_resource_usage WHERE worker_id=?';
    my $sth_delete = $self->prepare( $sql_delete );

    my $sql_insert = 'INSERT INTO worker_resource_usage (worker_id, exit_status, mem_megs, swap_megs, pending_sec, cpu_sec, lifespan_sec, exception_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
    my $sth_insert = $self->prepare( $sql_insert );

    my @not_ours = ();

    while( my ($process_id, $report_entry) = each %$report_entries ) {

        if( my $worker_id = $processid_2_workerid->{$process_id} ) {
            $sth_delete->execute( $worker_id );

            eval {
                $sth_insert->execute( $worker_id, @$report_entry{'exit_status', 'mem_megs', 'swap_megs', 'pending_sec', 'cpu_sec', 'lifespan_sec', 'exception_status'} );  # slicing hashref
                1;
            } or do {
                if($@ =~ /execute failed: Duplicate entry/s) {     # ignore the collision with another parallel beekeeper
                    $self->db->get_LogMessageAdaptor()->store_worker_message($worker_id, "Collision detected when storing resource_usage", 0 );
                } else {
                    die $@;
                }
            };
        } else {
            push @not_ours, $process_id;
            #warn "\tDiscarding process_id=$process_id as probably not ours because it could not be mapped to a Worker\n";
        }
    }
    $sth_delete->finish();
    $sth_insert->finish();
}


1;
