#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Queen

=head1 SYNOPSIS

  The Queen of the Hive based job control system

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

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods. 
  Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Queen;

use strict;
use POSIX;
use File::Path 'make_path';

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use Bio::EnsEMBL::Hive::Utils ('destringify', 'dir_revhash');  # NB: needed by invisible code
use Bio::EnsEMBL::Hive::AnalysisJob;
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
    my ($self, @args) = @_;

    my ($meadow_type, $meadow_name, $process_id, $exec_host, $resource_class_id, $resource_class_name,
        $no_write, $debug, $worker_log_dir, $hive_log_dir, $job_limit, $life_span, $no_cleanup, $retry_throwing_jobs, $can_respecialize) =

    rearrange([qw(meadow_type meadow_name process_id exec_host resource_class_id resource_class_name
                no_write debug worker_log_dir hive_log_dir job_limit life_span no_cleanup retry_throwing_jobs can_respecialize) ], @args);

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

    if( defined($resource_class_name) ) {
        my $rc = $self->db->get_ResourceClassAdaptor->fetch_by_name($resource_class_name)
            or die "resource_class with name='$resource_class_name' could not be fetched from the database";

        $resource_class_id = $rc->dbID;
    }

    my $sql = q{INSERT INTO worker (born, last_check_in, meadow_type, meadow_name, host, process_id, resource_class_id)
              VALUES (CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?)};

    my $sth = $self->prepare($sql);
    $sth->execute($meadow_type, $meadow_name, $exec_host, $process_id, $resource_class_id);
    my $worker_id = $self->dbc->db_handle->last_insert_id(undef, undef, 'worker', 'worker_id')
        or die "Could not insert a new worker";
    $sth->finish;

    if($hive_log_dir or $worker_log_dir) {
        my $dir_revhash = dir_revhash($worker_id);
        $worker_log_dir ||= $hive_log_dir .'/'. ($dir_revhash ? "$dir_revhash/" : '') .'worker_id_'.$worker_id;

        eval {
            make_path( $worker_log_dir );
            1;
        } or die "Could not create '$worker_log_dir' directory : $@";

        my $sth_add_log = $self->prepare( "UPDATE worker SET log_dir=? WHERE worker_id=?" );
        $sth_add_log->execute($worker_log_dir, $worker_id);
        $sth_add_log->finish;
    }

    my $worker = $self->fetch_by_dbID($worker_id)
        or die "Could not fetch worker with dbID=$worker_id";

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
    my ($self, $worker, @args) = @_;

    my ($analysis_id, $logic_name, $job_id, $force) =
        rearrange([qw(analysis_id logic_name job_id force) ], @args);

    if( scalar( grep {defined($_)} ($analysis_id, $logic_name, $job_id) ) > 1) {
        die "At most one of the options {-analysis_id, -logic_name, -job_id} can be set to pre-specialize a Worker";
    }

    my ($analysis, $stats, $special_batch);
    my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

    if($job_id or $analysis_id or $logic_name) {    # probably pre-specialized from command-line

        if($job_id) {
            print "resetting and fetching job for job_id '$job_id'\n";

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

            my $worker_id = $worker->dbID;
            if($job = $job_adaptor->reset_or_grab_job_by_dbID($job_id, $worker_id)) {
                $special_batch = [ $job ];
                $analysis_id = $job->analysis_id;
            } else {
                die "Could not claim job with dbID='$job_id' for worker with dbID='$worker_id'";
            }
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

        $stats = $analysis_stats_adaptor->fetch_by_analysis_id($analysis_id);
        $self->safe_synchronize_AnalysisStats($stats);

        unless($special_batch or $force) {    # do we really need to run this analysis?
            if($self->get_hive_current_load() >= 1.1) {
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
    } elsif( $stats = $self->suggest_analysis_to_specialize_by_rc_id_meadow_type($worker->resource_class_id, $worker->meadow_type) ) {

        $worker->analysis( undef ); # make sure we reset anything that was there before
        $analysis_id = $stats->analysis_id;
    } else {
        $worker->cause_of_death('NO_ROLE');
        die "No analysis suitable for the worker was found\n";
    }

        # now set it in the $worker:

    $worker->analysis_id( $analysis_id );

    my $sth_update_analysis_id = $self->prepare( "UPDATE worker SET analysis_id=? WHERE worker_id=?" );
    $sth_update_analysis_id->execute($worker->analysis_id, $worker->dbID);
    $sth_update_analysis_id->finish;

    if($special_batch) {
        $worker->special_batch( $special_batch );
    } else {    # count it as autonomous worker sharing the load of that analysis:

        $stats->update_status('WORKING');

        $analysis_stats_adaptor->decrease_required_workers($worker->analysis_id);
    }

        # The following increment used to be done only when no specific task was given to the worker,
        # thereby excluding such "special task" workers from being counted in num_running_workers.
        #
        # However this may be tricky to emulate by triggers that know nothing about "special tasks",
        # so I am (temporarily?) simplifying the accounting algorithm.
        #
    unless( $self->db->hive_use_triggers() ) {
        $analysis_stats_adaptor->increase_running_workers($worker->analysis_id);
    }
}


sub register_worker_death {
    my ($self, $worker, $self_burial) = @_;

    return unless($worker);

    my $cod = $worker->cause_of_death() || 'UNKNOWN';    # make sure we do not attempt to insert a void

                    # FIXME: make it possible to set the 'died' timestamp if we have detected it from logs:
    my $sql = qq{UPDATE worker SET died=CURRENT_TIMESTAMP
    } . ( $self_burial ? ',last_check_in=CURRENT_TIMESTAMP ' : '') . qq{
                    ,status='DEAD'
                    ,work_done='}. $worker->work_done . qq{'
                    ,cause_of_death='$cod'
                WHERE worker_id='}. $worker->dbID . qq{'};
    $self->dbc->do( $sql );

    if(my $analysis_id = $worker->analysis_id) {
        my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor;

        unless( $self->db->hive_use_triggers() ) {
            $analysis_stats_adaptor->decrease_running_workers($worker->analysis_id);
        }

        unless( $cod eq 'NO_WORK'
            or  $cod eq 'JOB_LIMIT'
            or  $cod eq 'HIVE_OVERLOAD'
            or  $cod eq 'LIFESPAN'
        ) {
                $self->db->get_AnalysisJobAdaptor->release_undone_jobs_from_worker($worker);
        }

            # re-sync the analysis_stats when a worker dies as part of dynamic sync system
        if($self->safe_synchronize_AnalysisStats($worker->analysis->stats)->status ne 'DONE') {
            # since I'm dying I should make sure there is someone to take my place after I'm gone ...
            # above synch still sees me as a 'living worker' so I need to compensate for that
            $analysis_stats_adaptor->increase_required_workers($worker->analysis_id);
        }
    }
}


sub check_for_dead_workers {    # scans the whole Valley for lost Workers (but ignores unreachagle ones)
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
            $mt_and_pid_to_worker_status{$meadow_type} ||= $meadow->status_of_all_our_workers;
        } else {
            $worker_status_counts{$meadow_type}{'UNREACHABLE'}++;

            next;   # Worker is unreachable from this Valley
        }

        my $process_id = $worker->process_id;
        if(my $status = $mt_and_pid_to_worker_status{$meadow_type}{$process_id}) { # can be RUN|PEND|xSUSP
            $worker_status_counts{$meadow_type}{$status}++;
        } else {
            $worker_status_counts{$meadow_type}{'LOST'}++;

            $mt_and_pid_to_lost_worker{$meadow_type}{$process_id} = $worker;
        }
    }

        # just a quick summary report:
    foreach my $meadow_type (keys %worker_status_counts) {
        warn "GarbageCollector:\t[$meadow_type Meadow:]\t".join(', ', map { "$_:$worker_status_counts{$meadow_type}{$_}" } keys %{$worker_status_counts{$meadow_type}})."\n\n";
    }

    while(my ($meadow_type, $pid_to_lost_worker) = each %mt_and_pid_to_lost_worker) {
        my $this_meadow = $valley->available_meadow_hash->{$meadow_type};

        if(my $lost_this_meadow = scalar(keys %$pid_to_lost_worker) ) {
            warn "GarbageCollector:\tDiscovered $lost_this_meadow lost $meadow_type Workers\n";

            my $wpid_to_cod = {};
            if($this_meadow->can('find_out_causes')) {
                $wpid_to_cod = $this_meadow->find_out_causes( keys %$pid_to_lost_worker );
                my $lost_with_known_cod = scalar(keys %$wpid_to_cod);
                warn "GarbageCollector:\tFound why $lost_with_known_cod of $meadow_type Workers died\n";
            } else {
                warn "GarbageCollector:\t$meadow_type meadow does not support post-mortem examination\n";
            }

            warn "GarbageCollector:\tReleasing the jobs\n";
            while(my ($process_id, $worker) = each %$pid_to_lost_worker) {
                $worker->cause_of_death( $wpid_to_cod->{$process_id} || 'UNKNOWN');
                $self->register_worker_death($worker);
            }
        }
    }

        # the following bit is completely Meadow-agnostic and only restores database integrity:
    if($check_buried_in_haste) {
        warn "GarbageCollector:\tChecking for Workers buried in haste...\n";
        my $buried_in_haste_list = $self->fetch_all_dead_workers_with_jobs();
        if(my $bih_number = scalar(@$buried_in_haste_list)) {
            warn "GarbageCollector:\tfound $bih_number jobs, reclaiming.\n\n";
            if($bih_number) {
                my $job_adaptor = $self->db->get_AnalysisJobAdaptor();
                foreach my $worker (@$buried_in_haste_list) {
                    $job_adaptor->release_undone_jobs_from_worker($worker);
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

    my $job_adaptor = $self->db->get_AnalysisJobAdaptor;
    my $job = $job_adaptor->reset_or_grab_job_by_dbID($job_id); 

    my $stats = $self->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id($job->analysis_id);
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


sub fetch_all_dead_workers_with_jobs {
    my $self = shift;

    return $self->fetch_all( "JOIN job j USING(worker_id) WHERE worker.status='DEAD' AND j.status NOT IN ('DONE', 'READY', 'FAILED', 'PASSED_ON') GROUP BY worker_id" );
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


  unless($self->db->hive_use_triggers()) {
      $analysisStats->total_job_count(0);
      $analysisStats->semaphored_job_count(0);
      $analysisStats->ready_job_count(0);
      $analysisStats->done_job_count(0);
      $analysisStats->failed_job_count(0);

            # ask for analysis_id to force MySQL to use existing index on (analysis_id, status)
      my $sql = "SELECT analysis_id, status, count(*) FROM job WHERE analysis_id=? GROUP BY analysis_id, status";
      my $sth = $self->prepare($sql);
      $sth->execute($analysisStats->analysis_id);

      my $done_here       = 0;
      my $done_elsewhere  = 0;
      my $total_job_count = 0;
      while (my ($dummy_analysis_id, $status, $job_count)=$sth->fetchrow_array()) {
    # print STDERR "$status: $job_count\n";

        $total_job_count += $job_count;

        if($status eq 'READY') {
            $analysisStats->ready_job_count($job_count);
        } elsif($status eq 'SEMAPHORED') {
            $analysisStats->semaphored_job_count($job_count);
        } elsif($status eq 'DONE') {
            $done_here = $job_count;
        } elsif($status eq 'PASSED_ON') {
            $done_elsewhere = $job_count;
        } elsif ($status eq 'FAILED') {
            $analysisStats->failed_job_count($job_count);
        }
      } # /while
      $sth->finish;

      $analysisStats->total_job_count( $total_job_count );
      $analysisStats->done_job_count( $done_here + $done_elsewhere );
  } # unless($self->db->hive_use_triggers())


        # compute the number of total required workers for this analysis (taking into account the jobs that are already running)
    my $analysis              = $analysisStats->get_analysis();
    my $scheduling_allowed    =  ( !defined( $analysisStats->hive_capacity ) or $analysisStats->hive_capacity )
                              && ( !defined( $analysis->analysis_capacity  ) or $analysis->analysis_capacity  );
    my $required_workers    = $scheduling_allowed
                            && POSIX::ceil( $analysisStats->ready_job_count() / $analysisStats->get_or_estimate_batch_size() );
    $analysisStats->num_required_workers( $required_workers );


    $analysisStats->check_blocking_control_rules();

    if($analysisStats->status ne 'BLOCKED') {
        $analysisStats->determine_status();
    }

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
        print "\t##########################################################\n";
        print "\t# Too many jobs in analysis '".$failed_analysis->logic_name."' FAILED #\n";
        print "\t##########################################################\n\n";
        if($filter_analysis and ($filter_analysis->dbID == $failed_analysis)) {
            $filter_analysis_failed = 1;
        }
    }

    return $filter_analysis ? $filter_analysis_failed : scalar(@$failed_analyses);
}


sub get_hive_current_load {
    my $self = shift;
    my $sql = qq{
        SELECT sum(1/hive_capacity)
        FROM worker w
        JOIN analysis_stats USING(analysis_id)
        WHERE w.status!='DEAD'
        AND hive_capacity IS NOT NULL
        AND hive_capacity>0
    };
    my $sth = $self->prepare($sql);
    $sth->execute();
    my ($load)=$sth->fetchrow_array();
    $sth->finish;
    return ($load || 0);
}


sub count_running_workers {
    my ($self, $analysis_id) = @_;

    return $self->count_all( "status!='DEAD'".($analysis_id ? " AND analysis_id=$analysis_id" : '') );
}


sub get_workers_rank {
    my ($self, $worker) = @_;

    return $self->count_all( "status!='DEAD' AND analysis_id=".$worker->analysis_id." AND worker_id<".$worker->dbID );
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
  printf("hive %1.3f%% complete (< %1.3f CPU_hrs) (%d todo + %d done + %d failed = %d total)\n", 
          $completed, $cpuhrs, $remaining, $done, $failed, $total);
  return $remaining;
}


sub print_analysis_status {
    my ($self, $filter_analysis) = @_;

    my $list_of_analyses = $filter_analysis ? [$filter_analysis] : $self->db->get_AnalysisAdaptor->fetch_all;
    foreach my $analysis (sort {$a->dbID <=> $b->dbID} @$list_of_analyses) {
        $analysis->stats->print_stats();
    }
}


sub print_running_worker_counts {
    my $self = shift;

    my $sql = qq{
        SELECT logic_name, count(*)
        FROM worker w
        JOIN analysis_base a USING(analysis_id)
        WHERE w.status!='DEAD'
        GROUP BY a.analysis_id
    };

    my $total_workers = 0;
    my $sth = $self->prepare($sql);
    $sth->execute();

    print "\n===== Stats of live Workers according to the Queen: ======\n";
    while((my $logic_name, my $worker_count)=$sth->fetchrow_array()) {
        printf("%30s : %d workers\n", $logic_name, $worker_count);
        $total_workers += $worker_count;
    }
    $sth->finish;
    printf("%30s : %d workers\n\n", '======= TOTAL =======', $total_workers);
}


=head2 monitor

  Arg[1]     : --none--
  Example    : $queen->monitor();
  Description: Monitors current throughput and store the result in the monitor
               table
  Exceptions : none
  Caller     : beekeepers and other external processes

=cut

sub monitor {
    my $self = shift;
    my $sql = qq{
        INSERT INTO monitor
        SELECT CURRENT_TIMESTAMP, count(*),
    } . {
        'mysql'     =>  qq{ sum(work_done/(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(born))),
                            sum(work_done/(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(born)))/count(*), },
        'sqlite'    =>  qq{ sum(work_done/(strftime('%s','now')-strftime('%s',born))),
                            sum(work_done/(strftime('%s','now')-strftime('%s',born)))/count(*), },
        'pgsql'     =>  qq{ sum(work_done/(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - born))),
                            sum(work_done/(EXTRACT(EPOCH FROM CURRENT_TIMESTAMP - born)))/count(*), },
    }->{ $self->dbc->driver }. qq{
        group_concat(DISTINCT logic_name)
        FROM worker w
        LEFT JOIN analysis_base USING (analysis_id)
        WHERE w.status!='DEAD'
    };
      
  my $sth = $self->prepare($sql);
  $sth->execute();
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
        $worker->cause_of_death( 'UNKNOWN' );  # well, maybe we could have investigated further...
        $self->register_worker_death($worker);
    }
}


sub suggest_analysis_to_specialize_by_rc_id_meadow_type {
    my $self                = shift;
    my $rc_id               = shift;
    my $meadow_type         = shift;

    my @suitable_analyses = @{ $self->db->get_AnalysisStatsAdaptor->fetch_all_by_suitability_rc_id_meadow_type( $rc_id, $meadow_type ) };

    foreach my $stats (@suitable_analyses) {

            #synchronize and double check that it can be run:
        $self->safe_synchronize_AnalysisStats($stats);
        return $stats if( ($stats->status ne 'BLOCKED') and ($stats->status ne 'SYNCHING') and ($stats->num_required_workers > 0) );
    }

    return undef;
}


1;
