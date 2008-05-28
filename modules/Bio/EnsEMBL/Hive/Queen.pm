#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

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
  gets $worker->batch_size() jobs from the analysis_job table, does its
  work, creates the next layer of analysis_job entries by interfacing to
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

  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX

  The rest of the documentation details each of the object methods. 
  Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Hive::Queen;

use strict;
use POSIX;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Hive::Worker;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Sys::Hostname;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;


our @ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);

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
               It creates an entry in the hive table, and returns a Worker object 
               based on that insert.  This guarantees that each worker registered
               in this queens hive is properly registered.
  Returntype : Bio::EnsEMBL::Hive::Worker
  Exceptions :
  Caller     :

=cut

sub create_new_worker {
  my ($self, @args) = @_;

  my ($analysis_id, $beekeeper ,$pid, $job, $no_write) =
     rearrange([qw(analysis_id beekeeper process_id job no_write) ], @args);

  my $analStatsDBA = $self->db->get_AnalysisStatsAdaptor;
  return undef unless($analStatsDBA);

  $analysis_id = $job->analysis_id if(defined($job));
  
  my $analysisStats;
  if($analysis_id) {
    $analysisStats = $analStatsDBA->fetch_by_analysis_id($analysis_id);
    $self->safe_synchronize_AnalysisStats($analysisStats);
    #return undef unless(($analysisStats->status ne 'BLOCKED') and ($analysisStats->num_required_workers > 0));
  } else {
    $analysisStats = $self->_pick_best_analysis_for_new_worker;
  }
  return undef unless($analysisStats);

  unless($job) {
    #go into autonomous mode
    return undef if($self->get_hive_current_load() >= 1.1);
    
    $analStatsDBA->decrease_needed_workers($analysisStats->analysis_id);
    $analStatsDBA->increase_running_workers($analysisStats->analysis_id);
    $analysisStats->print_stats;
    
    if($analysisStats->status eq 'BLOCKED') {
      print("Analysis is BLOCKED, can't create workers\n");
      return undef;
    }
    if($analysisStats->status eq 'DONE') {
      print("Analysis is DONE, don't need to create workers\n");
      return undef;
    }
  }
  
  my $host = hostname;
  $pid = $$ unless($pid);
  $beekeeper = '' unless($beekeeper);

  my $sql = q{INSERT INTO hive 
              (born, last_check_in, process_id, analysis_id, beekeeper, host)
              VALUES (NOW(), NOW(), ?,?,?,?)};

  my $sth = $self->prepare($sql);
  $sth->execute($pid, $analysisStats->analysis_id, $beekeeper, $host);
  my $hive_id = $sth->{'mysql_insertid'};
  $sth->finish;

  my $worker = $self->_fetch_by_hive_id($hive_id);
  $worker=undef unless($worker and $worker->analysis);

  if($worker and $analysisStats) {
    $analysisStats->update_status('WORKING');
  }
  
  $worker->_specific_job($job) if(defined($job));
  $worker->execute_writes(0) if($no_write);
  
  return $worker;
}


sub register_worker_death {
  my ($self, $worker) = @_;

  return unless($worker);

  # if called without a defined cause_of_death, assume catastrophic failure
  $worker->cause_of_death('FATALITY') unless(defined($worker->cause_of_death));
  unless ($worker->cause_of_death() eq "HIVE_OVERLOAD") {
    ## HIVE_OVERLOAD occurs after a successful update of the analysis_stats teble. (c.f. Worker.pm)
    $worker->analysis->stats->adaptor->decrease_running_workers($worker->analysis->stats->analysis_id);
  }

  my $sql = "UPDATE hive SET died=now(), last_check_in=now()";
  $sql .= " ,status='DEAD'";
  $sql .= " ,work_done='" . $worker->work_done . "'";
  $sql .= " ,cause_of_death='". $worker->cause_of_death ."'";
  $sql .= " WHERE hive_id='" . $worker->hive_id ."'";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;

  if($worker->cause_of_death eq "NO_WORK") {
    $self->db->get_AnalysisStatsAdaptor->update_status($worker->analysis->dbID, "ALL_CLAIMED");
  }
  if($worker->cause_of_death eq "FATALITY") {
    #print("FATAL DEATH Arrrrgggghhhhhhhh (hive_id=",$worker->hive_id,")\n");
    $self->db->get_AnalysisJobAdaptor->reset_dead_jobs_for_worker($worker);
  }
  
  # re-sync the analysis_stats when a worker dies as part of dynamic sync system
  if($self->safe_synchronize_AnalysisStats($worker->analysis->stats)->status ne 'DONE') {
    # since I'm dying I should make sure there is someone to take my place after I'm gone ...
    # above synch still sees me as a 'living worker' so I need to compensate for that
    $self->db->get_AnalysisStatsAdaptor->increase_needed_workers($worker->analysis->dbID);
  }

}


sub worker_check_in {
  my ($self, $worker) = @_;

  return unless($worker);
  my $sql = "UPDATE hive SET last_check_in=now()";
  $sql .= " ,work_done='" . $worker->work_done . "'";
  $sql .= " WHERE hive_id='" . $worker->hive_id ."'";

  my $sth = $self->prepare($sql);
  $sth->execute();
  $sth->finish;
  
  $self->safe_synchronize_AnalysisStats($worker->analysis->stats);
}


=head2 worker_grab_jobs

  Arg [1]           : Bio::EnsEMBL::Hive::Worker object $worker
  Example: 
    my $jobs  = $queen->worker_grab_jobs();
  Description: 
    For the specified worker, it will search available jobs, 
    and using the workers requested batch_size, claim/fetch that
    number of jobs, and then return them.
  Returntype : 
    reference to array of Bio::EnsEMBL::Hive::AnalysisJob objects
  Exceptions :
  Caller     :

=cut

sub worker_grab_jobs {
  my $self            = shift;
  my $worker          = shift;
  
  my $jobDBA = $self->db->get_AnalysisJobAdaptor;
  my $claim = $jobDBA->claim_jobs_for_worker($worker);
  my $jobs = $jobDBA->fetch_by_claim_analysis($claim, $worker->analysis->dbID);
  return $jobs;
}

=head2 reset_and_fetch_job_by_dbID

  Arg [1]: int $analysis_job_id
  Example: 
    my $job = $queen->reset_and_fetch_job_by_dbID($analysis_job_id);
  Description: 
    For the specified analysis_job_id it will fetch just that job, 
    reset it completely as if it has never run, and return it.  
    Specifying a specific job bypasses the safety checks, 
    thus multiple workers could be running the 
    same job simultaneously (use only for debugging).
  Returntype : 
    Bio::EnsEMBL::Hive::AnalysisJob object
  Exceptions :
  Caller     : beekeepers, runWorker.pl scripts

=cut

sub reset_and_fetch_job_by_dbID {
  my $self = shift;
  my $analysis_job_id = shift;
  
  my $jobDBA = $self->db->get_AnalysisJobAdaptor;
  $jobDBA->reset_job_by_dbID($analysis_job_id); 

  my $job = $jobDBA->fetch_by_dbID($analysis_job_id); 
  my $stats = $self->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id($job->analysis_id);
  $self->synchronize_AnalysisStats($stats);
  
  return $job;
}


sub worker_reclaim_job {
  my $self   = shift;
  my $worker = shift;
  my $job    = shift;

  return undef unless($job and $worker);
  $job->hive_id($worker->hive_id);
  $self->db->get_AnalysisJobAdaptor->reclaim_job($job);
  return $job;
}


sub worker_register_job_done {
  my $self = shift;
  my $worker = shift;
  my $job = shift;
  
  return unless($job);
  return unless($job->dbID and $job->adaptor and $job->hive_id);
  return unless($worker and $worker->analysis and $worker->analysis->dbID);
  
  $job->update_status('DONE');
}


sub flow_output_job {
  my $self = shift;
  my $job = shift;
  
  return unless($job);
  my $create_blocked_job = 0;
  $create_blocked_job = 1 if($job->status and ($job->status eq 'BLOCKED'));
  
  my @output_jobs;
  my $rules = $self->db->get_DataflowRuleAdaptor->fetch_from_analysis_job($job);
  foreach my $rule (@{$rules}) {
    my $job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => $job->input_id,
        -analysis       => $rule->to_analysis,
        -input_job_id   => $job->dbID,
        -block          => $create_blocked_job
    );
    my $job_url =  $rule->to_analysis->adaptor->db->dbc->url;
    $job_url .= "/analysis_job?dbID=" . $job_id;
    push @output_jobs, $job_url;
  }
  return \@output_jobs;
}


######################################
#
# Public API interface for beekeeper
#
######################################

sub fetch_overdue_workers {
  my ($self,$overdue_secs) = @_;

  $overdue_secs = 3600 unless(defined($overdue_secs));

  my $constraint = "h.cause_of_death='' ".
                   "AND (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(h.last_check_in))>$overdue_secs";
  return $self->_generic_fetch($constraint);
}

sub fetch_failed_workers {
  my $self = shift;
  my $constraint = "h.cause_of_death='FATALITY' ";
  return $self->_generic_fetch($constraint);
}


=head2 synchronize_hive

  Example    : $queen->synchronize_hive();
  Description: Runs through all analyses in the system and synchronizes
              the analysis_stats summary with the states in the analysis_job 
              and hive tables.  Then follows by checking all the blocking rules
              and blocks/unblocks analyses as needed.
  Exceptions : none
  Caller     : general

=cut

sub synchronize_hive {
  my $self = shift;

  my $start_time = time();

  my $allAnalysis = $self->db->get_AnalysisAdaptor->fetch_all;
  print("analyze ", scalar(@$allAnalysis), "\n");
  foreach my $analysis (@$allAnalysis) {
    my $stats = $analysis->stats;
    $self->synchronize_AnalysisStats($stats);
  }
  foreach my $analysis (@$allAnalysis) {
    $self->check_blocking_control_rules_for_AnalysisStats($analysis->stats);
  }
  print((time() - $start_time), " secs to synchronize_hive\n");
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
  return $stats unless($row_count == 1);
  #printf("got sync_lock on analysis_stats(%d)\n", $stats->analysis_id);
  
  #OK have the lock, go and do the sync
  $self->synchronize_AnalysisStats($stats);

  return $stats;
}


=head2 synchronize_AnalysisStats

  Arg [1]    : Bio::EnsEMBL::Hive::AnalysisStats object
  Example    : $self->synchronize($analysisStats);
  Description: Queries the analysis_job and hive tables to get summary counts
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
  $analysisStats->total_job_count(0);
  $analysisStats->unclaimed_job_count(0);
  $analysisStats->done_job_count(0);
  $analysisStats->failed_job_count(0);
  $analysisStats->num_required_workers(0);

  my $sql = "SELECT status, count(*) FROM analysis_job ".
            "WHERE analysis_id=? GROUP BY status";
  my $sth = $self->prepare($sql);
  $sth->execute($analysisStats->analysis_id);

  my $hive_capacity = $analysisStats->hive_capacity;

  while (my ($status, $count)=$sth->fetchrow_array()) {
# print STDERR "$status - $count\n";

    my $total = $analysisStats->total_job_count();
    $analysisStats->total_job_count($total + $count);

    if($status eq 'READY') {
      $analysisStats->unclaimed_job_count($count);
      my $numWorkers;
      if($analysisStats->batch_size > 0) {
        $numWorkers = POSIX::ceil($count / $analysisStats->batch_size);
      } else {
        my $job_msec = $analysisStats->avg_msec_per_job;
        $job_msec = 100 if($job_msec>0 and $job_msec<100);
        $numWorkers = POSIX::ceil(($count * $job_msec) / (3*60*1000)); 
        # guess num needed workers by total jobs / (num jobs a worker could do in 3 minutes)
      }
      $numWorkers=$count if($numWorkers==0);
      if($analysisStats->hive_capacity>0 and $numWorkers > $analysisStats->hive_capacity) {
        $numWorkers=$analysisStats->hive_capacity;
      }
      $analysisStats->num_required_workers($numWorkers);
    }
    if ($status eq 'DONE') { $analysisStats->done_job_count($count); }
    if ($status eq 'FAILED') { $analysisStats->failed_job_count($count); }
  }
  $sth->finish;

  $self->check_blocking_control_rules_for_AnalysisStats($analysisStats);

  if($analysisStats->status ne 'BLOCKED') {
    $analysisStats->determine_status();
  }

  #
  # adjust_stats_for_living_workers
  #
  
  if($analysisStats->hive_capacity > 0) {
    my $liveCount = $analysisStats->get_running_worker_count();

    my $numWorkers = $analysisStats->num_required_workers;

    my $capacityAdjust = ($numWorkers + $liveCount) - $analysisStats->hive_capacity;
    $numWorkers -= $capacityAdjust if($capacityAdjust > 0);
    $numWorkers=0 if($numWorkers<0);

    $analysisStats->num_required_workers($numWorkers);
  }

  $analysisStats->update;  #update and release sync_lock

  return $analysisStats;
}


sub check_blocking_control_rules_for_AnalysisStats
{
  my $self = shift;
  my $stats = shift;
  
  return unless($stats);

  #print("check ctrl on analysis ");  $stats->print_stats;
  my $ctrlRules = $self->db->get_AnalysisCtrlRuleAdaptor->
                  fetch_by_ctrled_analysis_id($stats->analysis_id);
  my $allRulesDone = 1;
  if(scalar @$ctrlRules > 0) {
    #print("HAS blocking_ctrl_rules to check\n");
    foreach my $ctrlrule (@{$ctrlRules}) {
      #use this method because the condition_analysis objects can be
      #network distributed to a different database so use it's adaptor to get
      #the AnalysisStats object
      #$ctrlrule->print_rule;
      my $condAnalysis = $ctrlrule->condition_analysis;
      my $condStats = $condAnalysis->stats if($condAnalysis);
      $allRulesDone = 0 unless($condStats and $condStats->status eq 'DONE');
      #print("  "); $condStats->print_stats;
    }

    if($allRulesDone) {
      if($stats->status eq 'BLOCKED') {
        #print("  UNBLOCK analysis : all conditions met\n");
        $stats->update_status('LOADING'); #trigger sync
      }
    } else {
      #print("  RE-BLOCK analysis : some conditions failed\n");
      $stats->update_status('BLOCKED');
    }
  }
}


sub get_num_failed_analyses
{
  my $self = shift;
  my $analysis = shift;

  my $statsDBA = $self->db->get_AnalysisStatsAdaptor;
  my $failed_analyses = $statsDBA->fetch_by_status('FAILED');
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
  my $sql = "SELECT sum(1/analysis_stats.hive_capacity) FROM hive, analysis_stats ".
            "WHERE hive.analysis_id=analysis_stats.analysis_id and cause_of_death ='' ".
            "AND analysis_stats.hive_capacity>0";
  my $sth = $self->prepare($sql);
  $sth->execute();
  (my $load)=$sth->fetchrow_array();
  $sth->finish;
  $load=0 unless($load);
  print("current hive load = $load\n");
  return $load;
}


sub get_num_running_workers {
  my $self = shift;
  my $sql = "SELECT count(*) FROM hive WHERE cause_of_death =''";
  my $sth = $self->prepare($sql);
  $sth->execute();
  (my $runningCount)=$sth->fetchrow_array();
  $sth->finish;
  $runningCount=0 unless($runningCount);
  print("current hive num_running_workers = $runningCount\n");
  return $runningCount;
}

sub enter_status {
  my ($self, $worker, $status) = @_;

  $self->dbc->do("UPDATE hive SET status = '$status' WHERE hive_id = ".$worker->hive_id);
}

=head2 get_num_needed_workers

  Arg[1]     : Bio::EnsEMBL::Analysis object (optional)
  Example    : $count = $queen->get_num_needed_workers();
  Description: Runs through the analyses in the system which are waiting
               for workers to be created for them.  Calculates the maximum
               number of workers needed to fill the current needs of the system
               If Arg[1] is defined, does it only for the given analysis.
  Exceptions : none
  Caller     : beekeepers and other external processes

=cut

sub get_num_needed_workers {
  my $self = shift;
  my $analysis = shift;

  my $statsDBA = $self->db->get_AnalysisStatsAdaptor;
  my $neededAnals = $statsDBA->fetch_by_needed_workers();
  my $deeper_stats_list = $statsDBA->fetch_by_status('LOADING', 'BLOCKED');
  push @$neededAnals, @$deeper_stats_list;

  return 0 unless($neededAnals);

  my $availableLoad = 1.0 - $self->get_hive_current_load();
  return 0 if($availableLoad <0.0);

  my $numWorkers = 0;
  foreach my $analysis_stats (@{$neededAnals}) {
    next if (defined $analysis && $analysis->dbID != $analysis_stats->analysis_id);

    #$analysis_stats->print_stats();

    #digging deeper under the surface so need to sync
    if(($analysis_stats->status eq 'LOADING') or ($analysis_stats->status eq 'BLOCKED')) {
      $self->synchronize_AnalysisStats($analysis_stats);
    }

    next if($analysis_stats->status eq 'BLOCKED');
    next if($analysis_stats->num_required_workers == 0);

    my $thisLoad = 0.0;
    if($analysis_stats->hive_capacity>0) {
      $thisLoad = $analysis_stats->num_required_workers * (1/$analysis_stats->hive_capacity);
    }

    if(($analysis_stats->hive_capacity<=0) or ($thisLoad < $availableLoad)) {
      $numWorkers += $analysis_stats->num_required_workers;
      $availableLoad -= $thisLoad;
      $analysis_stats->print_stats();
      printf("  %5d workers (%1.3f remaining-hive-load)\n", $numWorkers, $availableLoad);
    } else {
      my $workerCount = POSIX::ceil($availableLoad * $analysis_stats->hive_capacity);
      $numWorkers += $workerCount;
      $availableLoad -=  $workerCount * (1/$analysis_stats->hive_capacity);
      $analysis_stats->print_stats();
      printf("  %5d workers (%1.3f remaining-hive-load) use only %3d workers\n", $numWorkers, $availableLoad, $workerCount);
      last;
    }
    last if($availableLoad <= 0.0);
  }

  printf("need $numWorkers workers (availLoad=%1.5f)\n", $availableLoad);
  return $numWorkers;
}


sub get_hive_progress
{
  my $self = shift;
  my $sql = "SELECT sum(done_job_count), sum(failed_job_count), sum(total_job_count), ".
            "sum(unclaimed_job_count * analysis_stats.avg_msec_per_job)/1000/60/60 ".
            "FROM analysis_stats";
  my $sth = $self->prepare($sql);
  $sth->execute();
  my ($done, $failed, $total, $cpuhrs) = $sth->fetchrow_array();
  $sth->finish;
  $done=0 unless($done);
  $failed=0 unless($failed);
  $total=0 unless($total);
  my $completed=0.0;
  $completed = ((100.0 * ($done+$failed))/$total)  if($total>0);
  my $remaining = $total - $done - $failed;
  printf("hive %1.3f%% complete (< %1.3f CPU_hrs) (%d todo + %d done + %d failed = %d total)\n", 
          $completed, $cpuhrs, $remaining, $done, $failed, $total);
  return $done, $total, $cpuhrs;
}

sub print_hive_status
{
  my $self = shift;
  $self->print_analysis_status;
  $self->print_running_worker_status;
}


sub print_analysis_status
{
  my $self = shift;

  my $allStats = $self->db->get_AnalysisStatsAdaptor->fetch_all();
 
  foreach my $analysis_stats (@{$allStats}) {
    $analysis_stats->print_stats($self->{'verbose_stats'});
  }
}


sub print_running_worker_status
{
  my $self = shift;

  my $total = 0;
  print("HIVE LIVE WORKERS====\n");
  my $sql = "select logic_name, count(*) from hive, analysis ".
            "where hive.analysis_id=analysis.analysis_id and hive.cause_of_death='' ".
            "group by hive.analysis_id";
  my $sth = $self->prepare($sql);
  $sth->execute();
  while((my $logic_name, my $count)=$sth->fetchrow_array()) {
    printf("%20s : %d workers\n", $logic_name, $count);
    $total += $count;
  }
  printf("  %d total workers\n", $total);
  print("=====================\n");
  $sth->finish;
}

=head2 monitor

  Arg[1]     : --none--
  Example    : $queen->monitor();
  Description: Monitors current throughput and store the result in the monitor
               table
  Exceptions : none
  Caller     : beekeepers and other external processes

=cut

sub monitor
{
  my $self = shift;
  my $sql = qq{
      INSERT INTO monitor
      SELECT
          now(),
          count(*),
          sum(work_done/TIME_TO_SEC(TIMEDIFF(now(),born))),
          sum(work_done/TIME_TO_SEC(TIMEDIFF(now(),born)))/count(*),
          group_concat(DISTINCT logic_name)
      FROM hive left join analysis USING (analysis_id)
      WHERE cause_of_death = ""};
      
  my $sth = $self->prepare($sql);
  $sth->execute();
}


#
# INTERNAL METHODS
#
###################

sub _pick_best_analysis_for_new_worker {
  my $self = shift;

  my $statsDBA = $self->db->get_AnalysisStatsAdaptor;
  return undef unless($statsDBA);

  my ($stats) = @{$statsDBA->fetch_by_needed_workers(1)};
  if($stats) {
    #synchronize and double check that it can be run
    $self->safe_synchronize_AnalysisStats($stats);
    return $stats if(($stats->status ne 'BLOCKED') and ($stats->num_required_workers > 0));
  }

  # ok so no analyses 'need' workers.
  if ($self->get_num_failed_analyses()) {
    return undef;
  }
  # see if anything needs an update, in case there are
  # hidden jobs that haven't made it into the summary stats

  print("QUEEN: no obvious needed workers, need to dig deeper\n");
  my $stats_list = $statsDBA->fetch_by_status('LOADING', 'BLOCKED');
  foreach $stats (@$stats_list) {
    #$stats->print_stats();
    $self->safe_synchronize_AnalysisStats($stats);
    #$stats->print_stats();

    return $stats if(($stats->status ne 'BLOCKED') and ($stats->num_required_workers > 0));
  }

  ($stats) = @{$statsDBA->fetch_by_needed_workers(1)};
  return $stats if($stats);

  return undef;
}


=head2 _fetch_by_hive_id

  Arg [1]    : int $id
               the unique database identifier for the feature to be obtained
  Example    : $feat = $queen->fetch_by_dbID(1234);
  Description: Returns the feature created from the database defined by the
               the id $id.
  Returntype : Bio::EnsEMBL::Hive::Worker
  Exceptions : thrown if $id is not defined
  Caller     : general

=cut

sub _fetch_by_hive_id {
  my ($self,$id) = @_;

  unless(defined $id) {
    throw("fetch_by_dbID must have an id");
  }

  my @tabs = $self->_tables;

  my $constraint = "h.hive_id = $id";

  #return first element of _generic_fetch list
  my ($obj) = @{$self->_generic_fetch($constraint)};
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

  return (['hive', 'h']);
}

sub _columns {
  my $self = shift;

  return qw (h.hive_id
             h.analysis_id
             h.beekeeper
             h.host
             h.process_id
             h.work_done
             h.status
             h.born
             h.last_check_in
             h.died
             h.cause_of_death
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

    $worker->hive_id($column{'hive_id'});
    $worker->beekeeper($column{'beekeeper'});
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
