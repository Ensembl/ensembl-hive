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

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Utils ('destringify', 'dir_revhash');  # NB: needed by invisible code
use Bio::EnsEMBL::Hive::AnalysisJob;
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

    my ($meadow_type, $meadow_name, $process_id, $exec_host, $resource_class_id, $resource_class_name,
        $no_write, $debug, $worker_log_dir, $hive_log_dir, $job_limit, $life_span, $no_cleanup, $retry_throwing_jobs, $can_respecialize)
     = @flags{qw(-meadow_type -meadow_name -process_id -exec_host -resource_class_id -resource_class_name
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
        'host'              => $exec_host,
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


=head2 specialize_new_worker

  Description: If analysis_id or logic_name is specified it will try to specialize the Worker into this analysis.
               If not specified the Queen will analyze the hive and pick the most suitable analysis.
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub specialize_new_worker {
    my $self    = shift @_;
    my $worker  = shift @_;
    my %flags   = @_;

    my ($analysis_id, $logic_name, $job_id, $force)
     = @flags{qw(-analysis_id -logic_name -job_id -force)};

    if( scalar( grep {defined($_)} ($analysis_id, $logic_name, $job_id) ) > 1) {
        die "At most one of the options {-analysis_id, -logic_name, -job_id} can be set to pre-specialize a Worker";
    }

    my ($analysis, $stats);
    my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

    if($job_id or $analysis_id or $logic_name) {    # probably pre-specialized from command-line

        if($job_id) {
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
            $analysis_id = $job->analysis_id;
        }

        if($logic_name) {
            $analysis = $self->db->get_AnalysisAdaptor->fetch_by_logic_name($logic_name)
                or die "analysis with name='$logic_name' could not be fetched from the database";

            $analysis_id = $analysis->dbID;

        } elsif($analysis_id) {
            $analysis = $self->db->get_AnalysisAdaptor->fetch_by_dbID($analysis_id)
                or die "analysis with dbID='$analysis_id' could not be fetched from the database";
        }

        if( $worker->resource_class_id
        and $worker->resource_class_id != $analysis->resource_class_id) {
                die "resource_class of analysis ".$analysis->logic_name." is incompatible with this Worker's resource_class";
        }

        $stats = $analysis->stats;
        $self->safe_synchronize_AnalysisStats($stats);

        unless($job_id or $force) {    # do we really need to run this analysis?
            if($self->db->get_RoleAdaptor->get_hive_current_load() >= 1.1) {
                $worker->cause_of_death('HIVE_OVERLOAD');
                die "Hive is overloaded, can't specialize a worker";
            }
            if($stats->status eq 'BLOCKED') {
                die "Analysis is BLOCKED, can't specialize a worker";
            }
            if($stats->num_required_workers <= 0) {
                die "Analysis doesn't require extra workers at the moment";
            }
            if($stats->status eq 'DONE') {
                die "Analysis is DONE, and doesn't require workers";
            }
        }
            # probably scheduled by beekeeper.pl:
    } elsif( $stats = Bio::EnsEMBL::Hive::Scheduler::suggest_analysis_to_specialize_by_rc_id_meadow_type($self, $worker->resource_class_id, $worker->meadow_type) ) {

        $analysis_id = $stats->analysis_id;
    } else {
        $worker->cause_of_death('NO_ROLE');
        die "No analysis suitable for the worker was found\n";
    }

    my $role_adaptor = $self->db->get_RoleAdaptor;
    if( my $old_role = $worker->current_role ) {
        $role_adaptor->finalize_role( $old_role );
    }
    my $new_role = Bio::EnsEMBL::Hive::Role->new(
        'worker'        => $worker,
        'analysis_id'   => $analysis_id,
    );
    $role_adaptor->store( $new_role );
    $worker->current_role( $new_role );

    if($job_id) {
        my $role_id = $new_role->dbID;
        if( my $job = $self->db->get_AnalysisJobAdaptor->reset_or_grab_job_by_dbID($job_id, $role_id) ) {

            $worker->special_batch( [ $job ] );
        } else {
            die "Could not claim job with dbID='$job_id' for Role with dbID='$role_id'";
        }

    } else {    # count it as autonomous worker sharing the load of that analysis:

        $analysis_stats_adaptor->update_status($analysis_id, 'WORKING');

        $analysis_stats_adaptor->decrease_required_workers( $new_role->analysis_id );
    }

        # The following increment used to be done only when no specific task was given to the worker,
        # thereby excluding such "special task" workers from being counted in num_running_workers.
        #
        # However this may be tricky to emulate by triggers that know nothing about "special tasks",
        # so I am (temporarily?) simplifying the accounting algorithm.
        #
    unless( $self->db->hive_use_triggers() ) {
        $analysis_stats_adaptor->increase_running_workers( $new_role->analysis_id );
    }
}


sub register_worker_death {
    my ($self, $worker, $self_burial) = @_;

    return unless($worker);

    my $current_role    = $worker->current_role;
    my $worker_id       = $worker->dbID;
    my $work_done       = $worker->work_done;
    my $cause_of_death  = $worker->cause_of_death || 'UNKNOWN';    # make sure we do not attempt to insert a void
    my $worker_died     = $worker->died;

    if( $current_role ) {
        $current_role->when_finished( $worker_died );
        $self->db->get_RoleAdaptor->finalize_role( $current_role );
    }

    my $sql = "UPDATE worker SET status='DEAD', work_done='$work_done', cause_of_death='$cause_of_death'"
            . ( $self_burial ? ', last_check_in=CURRENT_TIMESTAMP ' : '' )
            . ( $worker_died ? ", died='$worker_died'" : ', died=CURRENT_TIMESTAMP' )
            . " WHERE worker_id='$worker_id' ";

    $self->dbc->do( $sql );

    if( my $analysis_id = $current_role && $current_role->analysis_id ) {
        my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

        unless( $self->db->hive_use_triggers() ) {
            $analysis_stats_adaptor->decrease_running_workers( $analysis_id );
        }

        unless( $cause_of_death eq 'NO_ROLE'
            or  $cause_of_death eq 'NO_WORK'
            or  $cause_of_death eq 'JOB_LIMIT'
            or  $cause_of_death eq 'HIVE_OVERLOAD'
            or  $cause_of_death eq 'LIFESPAN'
        ) {
                $self->db->get_AnalysisJobAdaptor->release_undone_jobs_from_role( $current_role );
        }

            # re-sync the analysis_stats when a worker dies as part of dynamic sync system
        if($self->safe_synchronize_AnalysisStats( $current_role->analysis->stats )->status ne 'DONE') {
            # since I'm dying I should make sure there is someone to take my place after I'm gone ...
            # above synch still sees me as a 'living worker' so I need to compensate for that
            $analysis_stats_adaptor->increase_required_workers( $analysis_id );
        }
    }
}


sub check_for_dead_workers {    # scans the whole Valley for lost Workers (but ignores unreachable ones)
    my ($self, $valley, $check_buried_in_haste) = @_;

    warn "GarbageCollector:\tChecking for lost Workers...\n";

    my $last_few_seconds            = 5;    # FIXME: It is probably a good idea to expose this parameter for easier tuning.
    my $queen_overdue_workers       = $self->fetch_overdue_workers( $last_few_seconds );    # check the workers we have not seen active during the $last_few_seconds
    my %mt_and_pid_to_worker_status = ();
    my %worker_status_counts        = ();
    my %mt_and_pid_to_lost_worker   = ();

    warn "GarbageCollector:\t[Queen:] out of ".scalar(@$queen_overdue_workers)." Workers that haven't checked in during the last $last_few_seconds seconds...\n";

    foreach my $worker (@$queen_overdue_workers) {

        my $meadow_type = $worker->meadow_type;
        if(my $meadow = $valley->find_available_meadow_responsible_for_worker($worker)) {

            $mt_and_pid_to_worker_status{$meadow_type} ||= $meadow->status_of_all_our_workers;  # only run this once per reachable Meadow

            my $process_id = $worker->process_id;
            if(my $status = $mt_and_pid_to_worker_status{$meadow_type}{$process_id}) {  # can be RUN|PEND|xSUSP
                $worker_status_counts{$meadow_type}{$status}++;
            } else {
                $worker_status_counts{$meadow_type}{'LOST'}++;

                $mt_and_pid_to_lost_worker{$meadow_type}{$process_id} = $worker;
            }
        } else {
            $worker_status_counts{$meadow_type}{'UNREACHABLE'}++;   # Worker is unreachable from this Valley
        }
    }

        # print a quick summary report:
    foreach my $meadow_type (keys %worker_status_counts) {
        warn "GarbageCollector:\t[$meadow_type Meadow:]\t".join(', ', map { "$_:$worker_status_counts{$meadow_type}{$_}" } keys %{$worker_status_counts{$meadow_type}})."\n\n";
    }

    my $role_adaptor = $self->db->get_RoleAdaptor;

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
                $worker->died(              $report_entries->{$process_id}{'died'} );
                $worker->cause_of_death(    $report_entries->{$process_id}{'cause_of_death'} );
                $worker->current_role( $role_adaptor->fetch_last_by_worker_id( $worker->dbID ) );
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

    $self->dbc->do("UPDATE worker SET last_check_in=CURRENT_TIMESTAMP, status='".$worker->status."', work_done='".$worker->work_done."' WHERE worker_id='".$worker->dbID."'");
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
            'mysql'     =>  "(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(last_check_in)) > $overdue_secs",
            'sqlite'    =>  "(strftime('%s','now')-strftime('%s',last_check_in)) > $overdue_secs",
            'pgsql'     =>  "EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - last_check_in) > $overdue_secs",
        }->{ $self->dbc->driver };

    return $self->fetch_all( $constraint );
}


=head2 synchronize_hive

  Arg [1]    : $filter_analysis (optional)
  Example    : $queen->synchronize_hive();
  Description: Runs through all analyses in the system and synchronizes
              the analysis_stats summary with the states in the job 
              and worker tables.  Then follows by checking all the blocking rules
              and blocks/unblocks analyses as needed.
  Exceptions : none
  Caller     : general

=cut

sub synchronize_hive {
  my $self          = shift;
  my $filter_analysis = shift; # optional parameter

  my $start_time = time();

  my $list_of_analyses = $filter_analysis ? [$filter_analysis] : $self->db->get_AnalysisAdaptor->fetch_all;

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
  Exceptions : none
  Caller     : general

=cut

sub safe_synchronize_AnalysisStats {
    my ($self, $stats) = @_;

    my $max_refresh_attempts = 5;
    while($stats->sync_lock and $max_refresh_attempts--) {   # another Worker/Beekeeper is synching this analysis right now
        sleep(1);
        $stats->refresh();  # just try to avoid collision
    }

    return $stats if($stats->status eq 'DONE');
    return $stats if(($stats->status eq 'WORKING') and
                   defined($stats->seconds_since_last_update) and
                   ($stats->seconds_since_last_update < 3*60));

        # try to claim the sync_lock
    my $sql = "UPDATE analysis_stats SET status='SYNCHING', sync_lock=1 ".
              "WHERE sync_lock=0 and analysis_id=" . $stats->analysis_id;
    my $row_count = $self->dbc->do($sql);  
    return $stats unless($row_count == 1);        # return the un-updated status if locked
  
        # if we managed to obtain the lock, let's go and perform the sync:
    $self->synchronize_AnalysisStats($stats);

    return $stats;
}


=head2 synchronize_AnalysisStats

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    : $self->synchronize($analysisStats);
  Description: Queries the job and worker tables to get summary counts
               and rebuilds the AnalysisStats object.  Then updates the
               analysis_stats table with the new summary info
  Returntype : newly synced Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub synchronize_AnalysisStats {
    my $self = shift;
    my $analysisStats = shift;

    return $analysisStats unless($analysisStats);
    return $analysisStats unless($analysisStats->analysis_id);

    $analysisStats->refresh(); ## Need to get the new hive_capacity for dynamic analyses

    my $job_counts = $self->db->hive_use_triggers() ? undef : $self->db->get_AnalysisJobAdaptor->fetch_job_counts_hashed_by_status( $analysisStats->analysis_id );

    $analysisStats->recalculate_from_job_counts( $job_counts );

    # $analysisStats->sync_lock(0); ## do we perhaps need it here?
    $analysisStats->update;  #update and release sync_lock

    return $analysisStats;
}


=head2 get_num_failed_analyses

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object (optional)
  Example    : if( $self->get_num_failed_analyses( $my_analysis )) { do_something; }
  Example    : my $num_failed_analyses = $self->get_num_failed_analyses();
  Description: Reports all failed analyses and returns
                either the number of total failed (if no $filter_analysis was provided)
                or 1/0, depending on whether $filter_analysis failed or not.
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub get_num_failed_analyses {
    my ($self, $filter_analysis) = @_;

    my $failed_analyses = $self->db->get_AnalysisAdaptor->fetch_all_failed_analyses();

    my $filter_analysis_failed = 0;

    foreach my $failed_analysis (@$failed_analyses) {
        warn "\t##########################################################\n";
        warn "\t# Too many jobs in analysis '".$failed_analysis->logic_name."' FAILED #\n";
        warn "\t##########################################################\n\n";
        if($filter_analysis and ($filter_analysis->dbID == $failed_analysis)) {
            $filter_analysis_failed = 1;
        }
    }

    return $filter_analysis ? $filter_analysis_failed : scalar(@$failed_analyses);
}


sub get_remaining_jobs_show_hive_progress {
  my $self = shift;
  my $sql = "SELECT sum(done_job_count), sum(failed_job_count), sum(total_job_count), ".
            "sum(ready_job_count * analysis_stats.avg_msec_per_job)/1000/60/60 ".
            "FROM analysis_stats";
  my $sth = $self->prepare($sql);
  $sth->execute();
  my ($done, $failed, $total, $cpuhrs) = $sth->fetchrow_array();
  $sth->finish;

  $done   ||= 0;
  $failed ||= 0;
  $total  ||= 0;
  my $completed = $total
    ? ((100.0 * ($done+$failed))/$total)
    : 0.0;
  my $remaining = $total - $done - $failed;
  warn sprintf("hive %1.3f%% complete (< %1.3f CPU_hrs) (%d todo + %d done + %d failed = %d total)\n",
          $completed, $cpuhrs, $remaining, $done, $failed, $total);
  return $remaining;
}


sub print_analysis_status {
    my ($self, $filter_analysis) = @_;

    my $list_of_analyses = $filter_analysis ? [$filter_analysis] : $self->db->get_AnalysisAdaptor->fetch_all;
    foreach my $analysis (sort {$a->dbID <=> $b->dbID} @$list_of_analyses) {
        print $analysis->stats->toString . "\n";
    }
}


=head2 register_all_workers_dead

  Example    : $queen->register_all_workers_dead();
  Description: Registers all workers dead
  Exceptions : none
  Caller     : beekeepers and other external processes

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
        SELECT meadow_type, meadow_name, min(born), max(died), count(*)
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

    my $sql_replace = 'REPLACE INTO worker_resource_usage (worker_id, exit_status, mem_megs, swap_megs, pending_sec, cpu_sec, lifespan_sec, exception_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
    my $sth_replace = $self->prepare( $sql_replace );

    my @not_ours = ();

    while( my ($process_id, $report_entry) = each %$report_entries ) {

        if( my $worker_id = $processid_2_workerid->{$process_id} ) {
            $sth_replace->execute( $worker_id, @$report_entry{'exit_status', 'mem_megs', 'swap_megs', 'pending_sec', 'cpu_sec', 'lifespan_sec', 'exception_status'} );  # slicing hashref
        } else {
            push @not_ours, $process_id;
            #warn "\tDiscarding process_id=$process_id as probably not ours because it could not be mapped to a Worker\n";
        }
    }
    $sth_replace->finish();
}


1;
