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
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Hive::Utils 'destringify';  # import 'destringify()'
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');


############################
#
# PUBLIC API for Workers
#
############################

=head2 create_new_worker

  Arg [1]    : $analysis_id (optional)
  Example    :
  Description: If analysis_id is specified it will try to create a worker based
               on that analysis.  If not specified the queen will analyze the hive
               and pick the analysis that has the most amount of work to be done.
               It creates an entry in the worker table, and returns a Worker object 
               based on that insert.  This guarantees that each worker registered
               in this queens hive is properly registered.
  Returntype : Bio::EnsEMBL::Hive::Worker
  Exceptions :
  Caller     :

=cut

sub create_new_worker {
  my ($self, @args) = @_;

  my (  $meadow_type, $meadow_name, $process_id, $exec_host,
        $rc_id, $logic_name, $analysis_id, $input_id, $job_id,
        $no_write, $debug, $worker_output_dir, $hive_output_dir, $job_limit, $life_span, $no_cleanup, $retry_throwing_jobs, $compile_module_once) =

 rearrange([qw(meadow_type meadow_name process_id exec_host
        rc_id logic_name analysis_id input_id job_id
        no_write debug worker_output_dir hive_output_dir job_limit life_span no_cleanup retry_throwing_jobs compile_module_once) ], @args);

    if($logic_name) {
        if($analysis_id) {
            die "You should either define -analysis_id or -logic_name, but not both\n";
        }
        if(my $analysis = $self->db->get_AnalysisAdaptor->fetch_by_logic_name($logic_name)) {
            $analysis_id = $analysis->dbID;
        } else {
            die "logic_name '$logic_name' could not be fetched from the database\n";
        }
    }

    my $job;

    if($input_id) {
        if($job_id) {
            die "You should either define -input_id or -job_id, but not both\n";

        } elsif($analysis_id) {
            $job = Bio::EnsEMBL::Hive::AnalysisJob->new(
                -INPUT_ID       => $input_id,
                -ANALYSIS_ID    => $analysis_id,
                -DBID           => -1,
            );
            print "creating a job outside the database\n";
            $job->print_job;
            $debug=1 unless(defined($debug));
            $hive_output_dir='' unless(defined($hive_output_dir)); # make it defined but empty/false
        } else {
            die "For creating a job outside the database either -analysis_id or -logic_name must also be defined\n";
        }
    }

    if($job_id) {
        if($analysis_id) {
            die "When you specify -job_id, please omit both -logic_name and -analysis_id to avoid confusion\n";
        } else {
            print "resetting and fetching job for job_id '$job_id'\n";

            my $job_adaptor = $self->db->get_AnalysisJobAdaptor;
            $job_adaptor->reset_job_by_dbID($job_id); 
            if($job = $job_adaptor->fetch_by_dbID($job_id)) {
                $analysis_id = $job->analysis_id;
            } else {
                die "job_id '$job_id' could not be fetched from the database\n";
            }
        }
    }

  
  my $analysis_stats_adaptor = $self->db->get_AnalysisStatsAdaptor or return undef;
  my $analysisStats;
  if($analysis_id) {
    $analysisStats = $analysis_stats_adaptor->fetch_by_analysis_id($analysis_id);
    $self->safe_synchronize_AnalysisStats($analysisStats);
    #return undef unless(($analysisStats->status ne 'BLOCKED') and ($analysisStats->num_required_workers > 0));
  } else {
    if( $analysisStats = $self->_pick_best_analysis_for_new_worker($rc_id) ) {
        print "Scheduler picked analysis_id=".$analysisStats->analysis_id()." for the worker\n";
    } else {
        print "Scheduler failed to pick analysis_id for the worker\n";
    }
  }
  return undef unless($analysisStats);

  unless($job) {
    #go into autonomous mode

    if($self->get_hive_current_load() >= 1.1) {
        print "Hive is overloaded, can't create a worker\n";
        return;
    }
    if($analysisStats->status eq 'BLOCKED') {
      print "Analysis is BLOCKED, can't create workers\n";
      return;
    }
    if($analysisStats->status eq 'DONE') {
      print "Analysis is DONE, don't need to create workers\n";
      return;
    }

    $analysis_stats_adaptor->decrease_required_workers($analysisStats->analysis_id);

    $analysisStats->print_stats;
  }
  
    # The following increment used to be done only when no specific task was given to the worker,
    # thereby excluding such "special task" workers from being counted in num_running_workers.
    #
    # However this may be tricky to emulate by triggers that know nothing about "special tasks",
    # so I am (temporarily?) simplifying the accounting algorithm.
    #
  unless( $self->db->hive_use_triggers() ) {
        $analysis_stats_adaptor->increase_running_workers($analysisStats->analysis_id);
  }

  my $sql = q{INSERT INTO worker 
              (born, last_check_in, meadow_type, meadow_name, process_id, host, analysis_id)
              VALUES (CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?,?,?,?,?)};

  my $sth = $self->prepare($sql);
  $sth->execute($meadow_type, $meadow_name, $process_id, $exec_host, $analysisStats->analysis_id);
  my $worker_id = $self->dbc->db_handle->last_insert_id(undef, undef, 'worker', 'worker_id');
  $sth->finish;

  my $worker = $self->fetch_by_dbID($worker_id);
  $worker=undef unless($worker and $worker->analysis);

  if($worker and $analysisStats) {
    $analysisStats->update_status('WORKING');
  }
  
  $worker->_specific_job($job) if($job);
  $worker->execute_writes(0) if($no_write);

    $worker->debug($debug) if($debug);
    $worker->worker_output_dir($worker_output_dir) if(defined($worker_output_dir));

    unless(defined($hive_output_dir)) {
        my $arrRef = $self->db->get_MetaContainer->list_value_by_key( 'hive_output_dir' );
        if( @$arrRef ) {
            $hive_output_dir = destringify($arrRef->[0]);
        } 
    }
    $worker->hive_output_dir($hive_output_dir);

    if($job_limit) {
      $worker->job_limit($job_limit);
      $worker->life_span(0);
    }
    if($life_span) {
      $worker->life_span($life_span * 60);
    }
    if($no_cleanup) { 
      $worker->perform_cleanup(0); 
    }
    if(defined $retry_throwing_jobs) {
        $worker->retry_throwing_jobs($retry_throwing_jobs);
    }
    if(defined $compile_module_once) {
        $worker->compile_module_once($compile_module_once);
    }

    return $worker;
}


sub register_worker_death {
  my ($self, $worker) = @_;

  return unless($worker);

  my $cod = $worker->cause_of_death();

  my $sql = "UPDATE worker SET died=CURRENT_TIMESTAMP, last_check_in=CURRENT_TIMESTAMP";
  $sql .= " ,status='DEAD'";
  $sql .= " ,work_done='" . $worker->work_done . "'";
  $sql .= " ,cause_of_death='$cod'";
  $sql .= " WHERE worker_id='" . $worker->dbID ."'";

  $self->dbc->do( $sql );

  unless( $self->db->hive_use_triggers() ) {
      $worker->analysis->stats->adaptor->decrease_running_workers($worker->analysis->stats->analysis_id);
  }

  if($cod eq 'NO_WORK') {
    $self->db->get_AnalysisStatsAdaptor->update_status($worker->analysis->dbID, 'ALL_CLAIMED');
  }
  if($cod eq 'FATALITY'
  or $cod eq 'MEMLIMIT'
  or $cod eq 'RUNLIMIT'
  or $cod eq 'KILLED_BY_USER') {
    $self->db->get_AnalysisJobAdaptor->release_undone_jobs_from_worker($worker);
  }
  
  # re-sync the analysis_stats when a worker dies as part of dynamic sync system
  if($self->safe_synchronize_AnalysisStats($worker->analysis->stats)->status ne 'DONE') {
    # since I'm dying I should make sure there is someone to take my place after I'm gone ...
    # above synch still sees me as a 'living worker' so I need to compensate for that
    $self->db->get_AnalysisStatsAdaptor->increase_required_workers($worker->analysis->dbID);
  }

}

sub check_for_dead_workers {    # scans the whole Valley for lost Workers (but ignores unreachagle ones)
    my ($self, $valley, $check_buried_in_haste) = @_;

    warn "GarbageCollector:\tChecking for lost Workers...\n";

    my $queen_worker_list           = $self->fetch_overdue_workers(0);
    my %mt_and_pid_to_worker_status = ();
    my %worker_status_counts        = ();
    my %mt_and_pid_to_lost_worker   = ();

    warn "GarbageCollector:\t[Queen:] we have ".scalar(@$queen_worker_list)." Workers alive.\n";

    foreach my $worker (@$queen_worker_list) {

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
                $worker->cause_of_death( $wpid_to_cod->{$process_id} || 'FATALITY');
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
    $job_adaptor->reset_job_by_dbID($job_id); 

    my $job = $job_adaptor->fetch_by_dbID($job_id); 
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

  my $constraint = "w.cause_of_death='' AND ".
                    ( ($self->dbc->driver eq 'sqlite')
                        ? "(strftime('%s','now')-strftime('%s',w.last_check_in))>$overdue_secs"
                        : "(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(w.last_check_in))>$overdue_secs");
  return $self->_generic_fetch($constraint);
}

sub fetch_failed_workers {
  my $self = shift;

  my $constraint = "w.cause_of_death='FATALITY' ";
  return $self->_generic_fetch($constraint);
}

sub fetch_all_dead_workers_with_jobs {
  my $self = shift;

  # SELECT w.* FROM worker h, job j WHERE w.worker_id=j.worker_id AND w.cause_of_death!='' AND j.status NOT IN ('DONE', 'READY','FAILED', 'PASSED_ON') GROUP BY w.worker_id

  my $constraint = "w.cause_of_death!='' ";
  my $join = [[['job', 'j'], " w.worker_id=j.worker_id AND j.status NOT IN ('DONE', 'READY', 'FAILED', 'PASSED_ON') GROUP BY w.worker_id"]];
  return $self->_generic_fetch($constraint, $join);
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

#  print STDERR "Checking blocking control rules:\n";
#  foreach my $analysis (@$list_of_analyses) {
#    my $open = $analysis->stats->check_blocking_control_rules();
#    print STDERR ($open ? 'o' : 'x');
#  }
#  print STDERR "\n";

  print STDERR ''.((time() - $start_time))." seconds to synchronize_hive\n\n";
}


=head2 safe_synchronize_AnalysisStats

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    : $self->synchronize($analysisStats);
  Description: Prewrapper around synchronize_AnalysisStats that does
               checks and grabs sync_lock before proceeding with sync.
               Used by distributed worker sync system to avoid contention.
  Exceptions : none
  Caller     : general

=cut

sub safe_synchronize_AnalysisStats {
  my $self = shift;
  my $stats = shift;

  return $stats unless($stats);
  return $stats unless($stats->analysis_id);
  return $stats if($stats->status eq 'SYNCHING');
  return $stats if($stats->status eq 'DONE');
  return $stats if($stats->sync_lock);
  return $stats if(($stats->status eq 'WORKING') and
                   ($stats->seconds_since_last_update < 3*60));

  # OK try to claim the sync_lock
  my $sql = "UPDATE analysis_stats SET status='SYNCHING', sync_lock=1 ".
            "WHERE sync_lock=0 and analysis_id=" . $stats->analysis_id;
  #print("$sql\n");
  my $row_count = $self->dbc->do($sql);  
  return $stats unless($row_count == 1);        # return the un-updated status if locked
  #printf("got sync_lock on analysis_stats(%d)\n", $stats->analysis_id);
  
      # since we managed to obtain the lock, let's go and perform the sync:
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
  my $hive_capacity = $analysisStats->hive_capacity;

  if($self->db->hive_use_triggers()) {

            my $job_count = $analysisStats->unclaimed_job_count();
            my $required_workers = POSIX::ceil( $job_count / $analysisStats->get_or_estimate_batch_size() );

                # adjust_stats_for_living_workers:
            if($hive_capacity > 0) {
                my $unfulfilled_capacity = $hive_capacity - $analysisStats->num_running_workers();

                if($unfulfilled_capacity < $required_workers ) {
                    $required_workers = (0 < $unfulfilled_capacity) ? $unfulfilled_capacity : 0;
                }
            }
            $analysisStats->num_required_workers( $required_workers );

  } else {
      $analysisStats->total_job_count(0);
      $analysisStats->unclaimed_job_count(0);
      $analysisStats->done_job_count(0);
      $analysisStats->failed_job_count(0);
      $analysisStats->num_required_workers(0);

      my $sql = "SELECT status, semaphore_count, count(*) FROM job ".
                "WHERE analysis_id=? GROUP BY status, semaphore_count";
      my $sth = $self->prepare($sql);
      $sth->execute($analysisStats->analysis_id);


      my $done_here       = 0;
      my $done_elsewhere  = 0;
      my $total_job_count = 0;
      while (my ($status, $semaphore_count, $job_count)=$sth->fetchrow_array()) {
    # print STDERR "$status: $job_count\n";

        $total_job_count += $job_count;

        if(($status eq 'READY') and ($semaphore_count<=0)) {
            $analysisStats->unclaimed_job_count($job_count);

            my $required_workers = POSIX::ceil( $job_count / $analysisStats->get_or_estimate_batch_size() );

                # adjust_stats_for_living_workers:
            if($hive_capacity > 0) {
                my $unfulfilled_capacity = $hive_capacity - $self->count_running_workers( $analysisStats->analysis_id() );

                if($unfulfilled_capacity < $required_workers ) {
                    $required_workers = (0 < $unfulfilled_capacity) ? $unfulfilled_capacity : 0;
                }
            }
            $analysisStats->num_required_workers( $required_workers );

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
  } # /unless $self->{'_hive_use_triggers'}

  $analysisStats->check_blocking_control_rules();

  if($analysisStats->status ne 'BLOCKED') {
    $analysisStats->determine_status();
  }

  # $analysisStats->sync_lock(0); ## do we perhaps need it here?
  $analysisStats->update;  #update and release sync_lock

  return $analysisStats;
}


sub get_num_failed_analyses {
  my ($self, $analysis) = @_;

  my $statsDBA = $self->db->get_AnalysisStatsAdaptor;
  my $failed_analyses = $statsDBA->fetch_by_statuses(['FAILED']);
  if ($analysis) {
    foreach my $this_failed_analysis (@$failed_analyses) {
      if ($this_failed_analysis->analysis_id == $analysis->dbID) {
        print "#########################################################\n",
            " Too many jobs failed for analysis ".$analysis->logic_name.". FAIL!!\n",
            "#########################################################\n\n";
        return 1;
      }
    }
    return 0;
  }

  if (@$failed_analyses) {
    print "##################################################\n",
        " Too many failed jobs. FAIL!!\n",
        "##################################################\n";
  }

  return scalar(@$failed_analyses);
}


sub get_hive_current_load {
  my $self = shift;
  my $sql = "SELECT sum(1/s.hive_capacity) FROM worker w, analysis_stats s ".
            "WHERE w.analysis_id=s.analysis_id and w.cause_of_death ='' ".
            "AND s.hive_capacity>0";
  my $sth = $self->prepare($sql);
  $sth->execute();
  (my $load)=$sth->fetchrow_array();
  $sth->finish;
  $load=0 unless($load);
  print("current hive load = $load\n");
  return $load;
}


sub count_running_workers {
    my ($self, $analysis_id) = @_;

    my $sql = "SELECT count(*) FROM worker WHERE cause_of_death =''"
        . ($analysis_id ? " AND analysis_id='$analysis_id'" : '');

    my $sth = $self->prepare($sql);
    $sth->execute();
    (my $running_workers_count)=$sth->fetchrow_array();
    $sth->finish();

    return $running_workers_count || 0;
}


=head2 schedule_workers

  Arg[1]     : Bio::EnsEMBL::Analysis object (optional)
  Example    : $count = $queen->schedule_workers();
  Description: Runs through the analyses in the system which are waiting
               for workers to be created for them.  Calculates the maximum
               number of workers needed to fill the current needs of the system
               If Arg[1] is defined, does it only for the given analysis.
  Exceptions : none
  Caller     : beekeepers and other external processes

=cut

sub schedule_workers {
  my ($self, $filter_analysis, $orig_pending_by_rc_id, $available_submit_limit) = @_;

  my $statsDBA                      = $self->db->get_AnalysisStatsAdaptor;
  my $clearly_needed_analyses       = $statsDBA->fetch_by_needed_workers(undef);
  my $potentially_needed_analyses   = $statsDBA->fetch_by_statuses(['LOADING', 'BLOCKED', 'ALL_CLAIMED']);
  my @all_analyses                  = (@$clearly_needed_analyses, @$potentially_needed_analyses);

  return {} unless(@all_analyses);

  my %pending_by_rc_id          = %{ $orig_pending_by_rc_id || {} };
  my $total_workers_to_run      = 0;
  my %workers_to_run_by_rc_id   = ();
  my $available_load            = 1.0 - $self->get_hive_current_load();

  foreach my $analysis_stats (@all_analyses) {
    last if ($available_load <= 0.0);
    last if (defined($available_submit_limit) and !$available_submit_limit);
    next if (defined $filter_analysis && $filter_analysis->dbID != $analysis_stats->analysis_id);

        #digging deeper under the surface so need to sync
    if(($analysis_stats->status eq 'LOADING') or ($analysis_stats->status eq 'BLOCKED') or ($analysis_stats->status eq 'ALL_CLAIMED')) {
      $self->synchronize_AnalysisStats($analysis_stats);
    }

    next if($analysis_stats->status eq 'BLOCKED');
    next if($analysis_stats->num_required_workers == 0);

        # FIXME: the following call *sometimes* returns a stale number greater than the number of workers actually needed for an analysis; -sync fixes it
    my $workers_this_analysis = $analysis_stats->num_required_workers;

    if(defined($available_submit_limit)) {                              # submit_limit total capping, if available
        if($workers_this_analysis > $available_submit_limit) {
            $workers_this_analysis = $available_submit_limit;
        }
        $available_submit_limit -= $workers_this_analysis;
    }

    if((my $hive_capacity = $analysis_stats->hive_capacity) > 0) {      # per-analysis hive_capacity capping, if available
        my $remaining_capacity_for_this_analysis = int($available_load * $hive_capacity);

        if($workers_this_analysis > $remaining_capacity_for_this_analysis) {
            $workers_this_analysis = $remaining_capacity_for_this_analysis;
        }

        $available_load -= 1.0*$workers_this_analysis/$hive_capacity;
    }

    my $curr_rc_id = $analysis_stats->resource_class_id;
    if($pending_by_rc_id{ $curr_rc_id }) {                              # per-rc_id capping by pending processes, if available
        my $pending_this_analysis = ($pending_by_rc_id{ $curr_rc_id } < $workers_this_analysis) ? $pending_by_rc_id{ $curr_rc_id } : $workers_this_analysis;

        $workers_this_analysis              -= $pending_this_analysis;
        $pending_by_rc_id{ $curr_rc_id }    -= $pending_this_analysis;
    }

    next unless($workers_this_analysis);    # do not autovivify the hash by a zero

    $total_workers_to_run += $workers_this_analysis;
    $workers_to_run_by_rc_id{ $curr_rc_id } += $workers_this_analysis;
    $analysis_stats->print_stats();
    printf("Scheduler suggests adding %d more workers of resource_class_id=%d for analysis_id=%d [%1.3f hive_load remaining]\n", $workers_this_analysis, $curr_rc_id, $analysis_stats->analysis_id, $available_load);
  }

  printf("Scheduler suggests adding a total of %d workers [%1.5f hive_load remaining]\n", $total_workers_to_run, $available_load);
  return \%workers_to_run_by_rc_id;
}


sub schedule_workers_resync_if_necessary {
    my ($self, $valley, $analysis) = @_;

    my $meadow              = $valley->get_current_meadow();

    my $pending_by_rc_id    = ($meadow->can('count_pending_workers_by_rc_id') and $meadow->config_get('PendingAdjust')) ? $meadow->count_pending_workers_by_rc_id() : {};
    my $submit_limit        = $meadow->config_get('SubmitWorkersMax');
    my $meadow_limit        = ($meadow->can('count_running_workers') and defined($meadow->config_get('TotalRunningWorkersMax'))) ? $meadow->config_get('TotalRunningWorkersMax') - $meadow->count_running_workers : undef;

    my $available_submit_limit = ($submit_limit and $meadow_limit)
                                    ? (($submit_limit<$meadow_limit) ? $submit_limit : $meadow_limit)
                                    : (defined($submit_limit) ? $submit_limit : $meadow_limit);

    my $workers_to_run_by_rc_id = $self->schedule_workers($analysis, $pending_by_rc_id, $available_submit_limit);

    unless( keys %$workers_to_run_by_rc_id or $self->get_hive_current_load() or $self->count_running_workers() ) {
        print "*** nothing is running and nothing to do (according to analysis_stats) => perform a hard resync\n" ;

        $self->check_for_dead_workers($valley, 1);
        $self->synchronize_hive($analysis);

        $workers_to_run_by_rc_id = $self->schedule_workers($analysis, $pending_by_rc_id, $available_submit_limit);
    }

    return $workers_to_run_by_rc_id;
}


sub get_remaining_jobs_show_hive_progress {
  my $self = shift;
  my $sql = "SELECT sum(done_job_count), sum(failed_job_count), sum(total_job_count), ".
            "sum(unclaimed_job_count * analysis_stats.avg_msec_per_job)/1000/60/60 ".
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
        $analysis->stats->print_stats($self->{'verbose_stats'});
    }
}


sub print_running_worker_counts {
  my $self = shift;

  print "\n===== Stats of live Workers according to the Queen: ======\n";
  my $sql = "SELECT logic_name, count(*) FROM worker, analysis ".
            "WHERE worker.analysis_id=analysis.analysis_id AND worker.cause_of_death='' ".
            "GROUP BY worker.analysis_id";

  my $total_workers = 0;
  my $sth = $self->prepare($sql);
  $sth->execute();
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
      SELECT
          CURRENT_TIMESTAMP,
          count(*),
  }. ( ($self->dbc->driver eq 'sqlite')
        ? qq{ sum(work_done/(strftime('%s','now')-strftime('%s',born))),
              sum(work_done/(strftime('%s','now')-strftime('%s',born)))/count(*), }
        : qq{ sum(work_done/(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(born))),
              sum(work_done/(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(born)))/count(*), }
  ). qq{
          group_concat(DISTINCT logic_name)
      FROM worker left join analysis USING (analysis_id)
      WHERE cause_of_death = ''
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

    my $overdueWorkers = $self->fetch_overdue_workers(0);
    foreach my $worker (@{$overdueWorkers}) {
        $worker->cause_of_death( 'FATALITY' );  # well, maybe we could have investigated further...
        $self->register_worker_death($worker);
    }
}


#
# INTERNAL METHODS
#
###################

sub _pick_best_analysis_for_new_worker {
  my $self  = shift;
  my $rc_id = shift;    # this parameter will need to percolate very deep

  my $statsDBA = $self->db->get_AnalysisStatsAdaptor;
  return undef unless($statsDBA);

  my ($stats) = @{$statsDBA->fetch_by_needed_workers(1, $rc_id)};
  if($stats) {
    #synchronize and double check that it can be run
    $self->safe_synchronize_AnalysisStats($stats);
    return $stats if(($stats->status ne 'BLOCKED') and ($stats->num_required_workers > 0) and (!defined($rc_id) or ($stats->resource_class_id == $rc_id)));
  }

  # ok so no analyses 'need' workers with the given $rc_id.
  if ($self->get_num_failed_analyses()) {
    return undef;
  }
  # see if anything needs an update, in case there are
  # hidden jobs that haven't made it into the summary stats

  print("QUEEN: no obvious needed workers, need to dig deeper\n");
  my $stats_list = $statsDBA->fetch_by_statuses(['LOADING', 'BLOCKED', 'ALL_CLAIMED']);
  foreach $stats (@$stats_list) {
    $self->safe_synchronize_AnalysisStats($stats);

    return $stats if(($stats->status ne 'BLOCKED') and ($stats->num_required_workers > 0) and (!defined($rc_id) or ($stats->resource_class_id == $rc_id)));
  }

    # does the following really ever help?
  ($stats) = @{$statsDBA->fetch_by_needed_workers(1, $rc_id)};
  return $stats;
}


=head2 fetch_by_dbID

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $queen->fetch_by_dbID(1234);
  Description: Returns the feature created from the database defined by the
               the id $id.
  Returntype : Bio::EnsEMBL::Hive::Worker
  Exceptions : thrown if $worker_id is not defined
  Caller     : general

=cut

sub fetch_by_dbID {
  my ($self, $worker_id) = @_;

  unless(defined $worker_id) {
    throw("fetch_by_dbID must have an id");
  }

  my ($obj) = @{$self->_generic_fetch( "w.worker_id = $worker_id" ) };
  return $obj;
}

=head2 _generic_fetch

  Arg [1]    : (optional) string $constraint
               An SQL query constraint (i.e. part of the WHERE clause)
  Arg [2]    : (optional) string $logic_name
               the logic_name of the analysis of the features to obtain
  Example    : $fts = $a->_generic_fetch('contig_id in (1234, 1235)', 'Swall');
  Description: Performs a database fetch and returns feature objects in
               contig coordinates.
  Returntype : listref of Bio::EnsEMBL::SeqFeature in contig coordinates
  Exceptions : none
  Caller     : BaseFeatureAdaptor, ProxyDnaAlignFeatureAdaptor::_generic_fetch

=cut

sub _generic_fetch {
  my ($self, $constraint, $join) = @_;

  my @tables = $self->_tables;
  my $columns = join(', ', $self->_columns());

  if ($join) {
    foreach my $single_join (@{$join}) {
      my ($tablename, $condition, $extra_columns) = @{$single_join};
      if ($tablename && $condition) {
        push @tables, $tablename;

        if($constraint) {
          $constraint .= " AND $condition";
        } else {
          $constraint = " $condition";
        }
      }
      if ($extra_columns) {
        $columns .= ", " . join(', ', @{$extra_columns});
      }
    }
  }

  #construct a nice table string like 'table1 t1, table2 t2'
  my $tablenames = join(', ', map({ join(' ', @$_) } @tables));

  my $sql = "SELECT $columns FROM $tablenames";

  my $default_where = $self->_default_where_clause;
  my $final_clause = $self->_final_clause;

  #append a where clause if it was defined
  if($constraint) {
    $sql .= " WHERE $constraint ";
    if($default_where) {
      $sql .= " AND $default_where ";
    }
  } elsif($default_where) {
    $sql .= " WHERE $default_where ";
  }

  #append additional clauses which may have been defined
  $sql .= " $final_clause";

  my $sth = $self->prepare($sql);
  $sth->execute;

#  print STDERR $sql,"\n";

  return $self->_objs_from_sth($sth);
}

sub _tables {
  my $self = shift;

  return (['worker', 'w']);
}

sub _columns {
  my $self = shift;

  return qw (w.worker_id
             w.analysis_id
             w.meadow_type
             w.meadow_name
             w.host
             w.process_id
             w.work_done
             w.status
             w.born
             w.last_check_in
             w.died
             w.cause_of_death
            );
}

sub _objs_from_sth {
  my ($self, $sth) = @_;

  my %column;
  $sth->bind_columns( \( @column{ @{$sth->{NAME_lc} } } ));

  my @workers = ();

  while ($sth->fetch()) {
    my $worker = new Bio::EnsEMBL::Hive::Worker;
    $worker->init;

    $worker->dbID($column{'worker_id'});
    $worker->meadow_type($column{'meadow_type'});
    $worker->meadow_name($column{'meadow_name'});
    $worker->host($column{'host'});
    $worker->process_id($column{'process_id'});
    $worker->work_done($column{'work_done'});
    $worker->status($column{'status'});
    $worker->born($column{'born'});
    $worker->last_check_in($column{'last_check_in'});
    $worker->died($column{'died'});
    $worker->cause_of_death($column{'cause_of_death'});
    $worker->queen($self);
    $worker->db($self->db);

    if($column{'analysis_id'} and $self->db->get_AnalysisAdaptor) {
      $worker->analysis($self->db->get_AnalysisAdaptor->fetch_by_dbID($column{'analysis_id'}));
    }

    push @workers, $worker;
  }
  $sth->finish;

  return \@workers
}

sub _default_where_clause {
  my $self = shift;
  return '';
}

sub _final_clause {
  my $self = shift;
  return '';
}


1;
