#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Worker

=head1 DESCRIPTION

  Object which encapsulates the details of how to find jobs, how to run those
  jobs, and then check the rules to create the next jobs in the chain.
  Essentially knows where to find data, how to process data, and where to
  put it when it is done (put in next persons INBOX) so the next Worker
  in the chain can find data to work on.

  Hive based processing is a concept based on a more controlled version
  of an autonomous agent type system.  Each worker is not told what to do
  (like a centralized control system - like the current pipeline system)
  but rather queries a central database for jobs (give me jobs).

  Each worker is linked to an analysis_id, registers its self on creation
  into the Hive, creates a RunnableDB instance of the Analysis->module,
  gets relevant configuration information from the database, does its
  work, creates the next layer of job entries by interfacing to
  the DataflowRuleAdaptor to determine the analyses it needs to pass its
  output data to and creates jobs on the database of the next analysis.
  It repeats this cycle until it has lived its lifetime or until there are no
  more jobs left to process.
  The lifetime limit is a safety limit to prevent these from 'infecting'
  a system and sitting on a compute node for longer than is socially exceptable.
  This is primarily needed on compute resources like an LSF system where jobs
  are not preempted and run until they are done.

  The Queens primary job is to create Workers to get the work down.
  As part of this, she is also responsible for summarizing the status of the
  analyses by querying the jobs, summarizing, and updating the
  analysis_stats table.  From this she is also responsible for monitoring and
  'unblocking' analyses via the analysis_ctrl_rules.
  The Queen is also responsible for freeing up jobs that were claimed by Workers
  that died unexpectantly so that other workers can take over the work.  

  The Beekeeper is in charge of interfacing between the Queen and a compute resource
  or 'compute farm'.  Its job is to query Queens if they need any workers and to
  send the requested number of workers to open machines via the runWorker.pl script.
  It is also responsible for interfacing with the Queen to identify workers which died
  unexpectantly so that she can free the dead workers unfinished jobs.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Worker;

use strict;
use POSIX;

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Hive::Limiter;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Utils::RedirectStack;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;
use Bio::EnsEMBL::Hive::Utils ('stringify');

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );


sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

    my($analysis_id, $meadow_type, $meadow_name, $host, $process_id, $resource_class_id, $work_done, $status, $born, $last_check_in, $died, $cause_of_death, $log_dir) =
        rearrange([qw(analysis_id meadow_type meadow_name host process_id resource_class_id work_done status born last_check_in died cause_of_death log_dir) ], @_);

    $self->analysis_id($analysis_id)                if(defined($analysis_id));
    $self->meadow_type($meadow_type)                if(defined($meadow_type));
    $self->meadow_name($meadow_name)                if(defined($meadow_name));
    $self->host($host)                              if(defined($host));
    $self->process_id($process_id)                  if(defined($process_id));
    $self->resource_class_id($resource_class_id)    if(defined($resource_class_id));
    $self->work_done($work_done)                    if(defined($work_done));
    $self->status($status)                          if(defined($status));
    $self->born($born)                              if(defined($born));
    $self->last_check_in($last_check_in)            if(defined($last_check_in));
    $self->died($died)                              if(defined($died));
    $self->cause_of_death($cause_of_death)          if(defined($cause_of_death));
    $self->log_dir($log_dir)                        if(defined($log_dir));

    return $self;
}


sub init {
    my $self = shift;

    my $lifespan_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    $lifespan_stopwatch->_unit(1); # count in seconds (default is milliseconds)
    $lifespan_stopwatch->restart;
    $self->lifespan_stopwatch( $lifespan_stopwatch );

    return $self;
}


## Storable object's getters/setters:


sub analysis_id {
    my $self = shift;
    $self->{'_analysis_id'} = shift if(@_);
    return $self->{'_analysis_id'};
}


sub meadow_type {
    my $self = shift;
    $self->{'_meadow_type'} = shift if(@_);
    return $self->{'_meadow_type'};
}


sub meadow_name {
    my $self = shift;
    $self->{'_meadow_name'} = shift if(@_);
    return $self->{'_meadow_name'};
}


sub host {
    my $self = shift;
    $self->{'_host'} = shift if(@_);
    return $self->{'_host'};
}


sub process_id {
    my $self = shift;
    $self->{'_process_id'} = shift if(@_);
    return $self->{'_process_id'};
}


sub resource_class_id {
    my $self = shift;
    $self->{'_resource_class_id'} = shift if(@_);
    return $self->{'_resource_class_id'};
}


sub work_done {
    my $self = shift;
    $self->{'_work_done'} = shift if(@_);
    return $self->{'_work_done'} || 0;
}


sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    return $self->{'_status'};
}


sub born {
    my $self = shift;
    $self->{'_born'} = shift if(@_);
    return $self->{'_born'};
}


sub last_check_in {
    my $self = shift;
    $self->{'_last_check_in'} = shift if(@_);
    return $self->{'_last_check_in'};
}


sub died {
    my $self = shift;
    $self->{'_died'} = shift if(@_);
    return $self->{'_died'};
}


sub cause_of_death {
    my $self = shift;
    $self->{'_cause_of_death'} = shift if(@_);
    return $self->{'_cause_of_death'};
}


=head2 log_dir

  Arg [1] : (optional) string directory path
  Title   : log_dir
  Usage   : $worker_log_dir = $self->log_dir;
            $self->log_dir($worker_log_dir);
  Description: Storable getter/setter attribute for the directory where STDOUT and STRERR of the worker will be redirected to.
               In this directory each job will have its own .out and .err files.
  Returntype : string

=cut

sub log_dir {
    my $self = shift;
    $self->{'_log_dir'} = shift if(@_);
    return $self->{'_log_dir'};
}



## Non-Storable attributes:

sub debug {
  my $self = shift;
  $self->{'_debug'} = shift if(@_);
  $self->{'_debug'}=0 unless(defined($self->{'_debug'}));
  return $self->{'_debug'};
}


sub execute_writes {
  my $self = shift;
  $self->{'_execute_writes'} = shift if(@_);
  $self->{'_execute_writes'}=1 unless(defined($self->{'_execute_writes'}));
  return $self->{'_execute_writes'};
}


sub special_batch {
  my $self = shift;
  $self->{'_special_batch'} = shift if(@_);
  return $self->{'_special_batch'};
}


sub perform_cleanup {
  my $self = shift;
  $self->{'_perform_cleanup'} = shift if(@_);
  $self->{'_perform_cleanup'} = 1 unless(defined($self->{'_perform_cleanup'}));
  return $self->{'_perform_cleanup'};
}


# this is a setter/getter that defines default behaviour when a job throws: should it be retried or not?

sub retry_throwing_jobs {
    my $self = shift @_;

    $self->{'_retry_throwing_jobs'} = shift @_ if(@_);
    return defined($self->{'_retry_throwing_jobs'}) ? $self->{'_retry_throwing_jobs'} : 1;
}


sub can_respecialize {
    my $self = shift;
    $self->{'_can_respecialize'} = shift if(@_);
    return $self->{'_can_respecialize'};
}


=head2 analysis

  Arg [1] : (optional) Bio::EnsEMBL::Hive::Analysis $value
  Title   :   analysis
  Usage   :   $analysis = $self->analysis;
              $self->analysis($analysis);
  Description: Get/Set analysis object of this Worker
  DefaultValue : undef
  Returntype : Bio::EnsEMBL::Hive::Analysis object

=cut

sub analysis {
    my $self = shift @_;

    if(@_) {    # setter mode
        $self->{'_analysis'} = shift @_;
    } elsif(! $self->{'_analysis'} ) {
        if(my $analysis_id = $self->analysis_id()) {
            $self->{'_analysis'} = $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID( $analysis_id )
                or die "Could not fetch analysis for analysis_id=$analysis_id";
        } else {
            die "analysis_id not defined, could not fetch Hive::Analysis object";
        }
    }

    return $self->{'_analysis'};
}


=head2 life_span

  Arg [1] : (optional) integer $value (in seconds)
  Title   :   life_span
  Usage   :   $value = $self->life_span;
              $self->life_span($new_value);
  Description: Defines the maximum time a worker can live for. Workers are always
               allowed to complete the jobs they get, but whether they can
               do multiple rounds of work is limited by their life_span
  DefaultValue : 3600 (60 minutes)
  Returntype : integer scalar

=cut

sub life_span { # default life_span = 60minutes
    my ($self, $value) = @_;

    if(defined($value)) {               # you can still set it to 0 and avoid having the limit on lifespan
        $self->{'_life_span'} = $value;
    } elsif(!defined($self->{'_life_span'})) {
        $self->{'_life_span'} = 60*60;
    }
    return $self->{'_life_span'};
}

sub lifespan_stopwatch {
    my $self = shift @_;

    if(@_) {
        $self->{'_lifespan_stopwatch'} = shift @_;
    }
    return $self->{'_lifespan_stopwatch'};
}

sub life_span_limit_reached {
    my $self = shift @_;

    if( $self->life_span() ) {
        my $alive_for_secs = $self->lifespan_stopwatch->get_elapsed;
        if($alive_for_secs > $self->life_span() ) {
            return $alive_for_secs;
        }
    }
    return 0;
}


=head2 job_limiter

  Title   :   job_limiter
  Arg [1] :   (optional) integer $value
  Usage   :   $limiter_obj = $self->job_limiter;
              $self->job_limiter($new_value);
  Description: The maximum number of jobs to be done by the Worker can be limited by the given number.
               A worker 'dies' when either the 'life_span' or 'job_limit' is exceeded.
  DefaultValue : undef (relies on life_span to limit life of worker)
  Returntype : Hive::Limiter object

=cut

sub job_limiter {
    my $self=shift;
    if( scalar(@_) or !defined($self->{'_job_limiter'}) ) {
        $self->{'_job_limiter'} = Bio::EnsEMBL::Hive::Limiter->new("Total number of jobs this Worker is allowed to take", shift @_);
    }
    return $self->{'_job_limiter'};
}


sub more_work_done {
    my ($self, $job_partial_timing) = @_;

    $self->{'_work_done'}++;

    while( my ($state, $partial_timing_in_state) = each %$job_partial_timing ) {
        $self->{'_interval_partial_timing'}{$state} += $partial_timing_in_state;
    }
}


# By maintaining this information we attempt to detect worker contamination without the user specifically telling us about it
#
# Ideally we should be doing an *ALIGNMENT* of error messages (allowing for some numerical IDs to differ),
# but at the moment we assume all errors identical. If the worker failed two jobs in a row - let him die.

sub prev_job_error {
    my $self = shift @_;

    $self->{'_prev_job_error'} = shift if(@_);
    return $self->{'_prev_job_error'};
}

sub runnable_object {
    my $self = shift @_;

    $self->{'_runnable_object'} = shift @_ if(@_);
    return $self->{'_runnable_object'};
}


sub get_stdout_redirector {
    my $self = shift;

    return $self->{_stdout_redirector} ||= Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDOUT);
}

sub get_stderr_redirector {
    my $self = shift;

    return $self->{_stderr_redirector} ||= Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDERR);
}


sub worker_say {
    my ($self, $msg) = @_;

    my $worker_id     = $self->dbID();
    my $analysis_name = $self->analysis_id ? $self->analysis->logic_name.'('.$self->analysis_id.')' : '';
    print "Worker $worker_id [ $analysis_name ] $msg\n";
}


sub toString {
    my $self = shift @_;

    return join(', ',
            'analysis='.($self->analysis_id ? $self->analysis->logic_name.'('.$self->analysis_id.')' : 'UNSPECIALIZED'),
            'resource_class_id='.($self->resource_class_id || 'NULL'),
            'meadow='.$self->meadow_type.'/'.$self->meadow_name,
            'process='.$self->process_id.'@'.$self->host,
            'last_check_in='.$self->last_check_in,
            'batch_size='.($self->analysis_id ? $self->analysis->stats->get_or_estimate_batch_size() : 'UNSPECIALIZED'),
            'job_limit='.($self->job_limiter->available_capacity() || 'NONE'),
            'life_span='.($self->life_span || 'UNLIM'),
            'worker_log_dir='.($self->log_dir || 'STDOUT/STDERR'),
    );
}


###############################
#
# WORK section
#
###############################


=head2 run

  Title   :   run
  Usage   :   $worker->run;
  Description: 
    This is a self looping autonomous function to process jobs.
    First all STDOUT/STDERR is rediected, then looping commences.
    Looping consists of 
      1) claiming jobs,
      2) processing those jobs through an instance of the 'module class' of 
         the analysis asigned to this worker,  
      3) updating the job, analysis_stats, and hive tables to track the 
         progress of the job, the analysis and this worker.
    Looping stops when any one of these are met:
      1) there is no more jobs to process 
      2) job_limit is reached
      3) life_span has been reached.
  Returntype : none

=cut

sub run {
    my ($self, $specialization_arglist) = @_;

    if( my $worker_log_dir = $self->log_dir ) {
        $self->get_stdout_redirector->push( $worker_log_dir.'/worker.out' );
        $self->get_stderr_redirector->push( $worker_log_dir.'/worker.err' );
    }

    my $min_batch_time  = Bio::EnsEMBL::Hive::AnalysisStats::min_batch_time();
    my $job_adaptor     = $self->adaptor->db->get_AnalysisJobAdaptor;

    print "\n"; # to clear beekeeper's prompt in case output is not logged
    $self->worker_say( $self->toString() );
    $self->specialize_and_compile_wrapper( $specialization_arglist );

    while (!$self->cause_of_death) {  # Worker's lifespan loop (ends only when the worker dies for any reason)

        my $batches_stopwatch           = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart();
        my $jobs_done_by_batches_loop   = 0; # by all iterations of internal loop
        $self->{'_interval_partial_timing'} = {};

        if( my $special_batch = $self->special_batch() ) {
            $jobs_done_by_batches_loop += $self->run_one_batch( $special_batch );
            $self->cause_of_death('JOB_LIMIT');
        } else {    # a proper "BATCHES" loop

            while (!$self->cause_of_death and $batches_stopwatch->get_elapsed < $min_batch_time) {

                if( scalar(@{ $job_adaptor->fetch_all_incomplete_jobs_by_worker_id( $self->dbID ) }) ) {
                    my $msg = "Lost control. Check your Runnable for loose 'next' statements that are not part of a loop";
                    $self->worker_say( $msg );
                    $self->cause_of_death('CONTAMINATED');
                    $job_adaptor->release_undone_jobs_from_worker($self, $msg);

                } elsif( $self->job_limiter->reached()) {
                    $self->worker_say( "job_limit reached (".$self->work_done." jobs completed)" );
                    $self->cause_of_death('JOB_LIMIT');

                } elsif ( my $alive_for_secs = $self->life_span_limit_reached()) {
                    $self->worker_say( "life_span limit reached (alive for $alive_for_secs secs)" );
                    $self->cause_of_death('LIFESPAN');

                } else {
                    my $desired_batch_size = $self->analysis->stats->get_or_estimate_batch_size();
                    $desired_batch_size = $self->job_limiter->preliminary_offer( $desired_batch_size );

                    my $actual_batch = $job_adaptor->grab_jobs_for_worker( $self, $desired_batch_size );
                    if(scalar(@$actual_batch)) {
                        my $jobs_done_by_this_batch = $self->run_one_batch( $actual_batch );
                        $jobs_done_by_batches_loop += $jobs_done_by_this_batch;
                        $self->job_limiter->final_decision( $jobs_done_by_this_batch );
                    } else {
                        $self->cause_of_death('NO_WORK');
                    }
                }
            }
        }

        # The following two database-updating operations are resource-expensive (all workers hammering the same database+tables),
        # so they are not allowed to happen too frequently (not before $min_batch_time of work has been done)
        #
        if($jobs_done_by_batches_loop) {

            $self->adaptor->db->get_AnalysisStatsAdaptor->interval_update_work_done(
                $self->analysis->dbID,
                $jobs_done_by_batches_loop,
                $batches_stopwatch->get_elapsed,
                $self->{'_interval_partial_timing'}{'FETCH_INPUT'}  || 0,
                $self->{'_interval_partial_timing'}{'RUN'}          || 0,
                $self->{'_interval_partial_timing'}{'WRITE_OUTPUT'} || 0,
            );
        }

        # A mechanism whereby workers can be caused to exit even if they were doing fine:
        #
        # FIXME: The following check is not *completely* correct, as it assumes hive_capacity is "local" to the analysis:
        if (!$self->cause_of_death) {
            my $stats = $self->analysis->stats;
            if( defined($stats->hive_capacity)
            and 0 <= $stats->hive_capacity
            and $stats->hive_capacity < $stats->num_running_workers
            ) {
                $self->cause_of_death('HIVE_OVERLOAD');
            }
        }

        if( $self->cause_of_death() eq 'NO_WORK') {
            $self->adaptor->db->get_AnalysisStatsAdaptor->update_status($self->analysis_id, 'ALL_CLAIMED');
            
            if( $self->can_respecialize and !$specialization_arglist ) {
                $self->cause_of_death(undef);
                $self->specialize_and_compile_wrapper();
            }
        }

    }     # /Worker's lifespan loop

        # have runnable clean up any global/process files/data it may have created
    if($self->perform_cleanup) {
        if(my $runnable_object = $self->runnable_object()) {    # the temp_directory is actually kept in the Process object:
            $runnable_object->cleanup_worker_temp_directory();
        }
    }

    $self->adaptor->register_worker_death($self);

    if($self->debug) {
        $self->worker_say( 'AnalysisStats :'.$self->analysis->stats->toString ) if($self->analysis_id());
        $self->worker_say( 'dbc '.$self->adaptor->db->dbc->disconnect_count. ' disconnect cycles' );
    }

    $self->worker_say( "Having completed ".$self->work_done." jobs the Worker exits : ".$self->cause_of_death  );

    if( $self->log_dir ) {
        $self->get_stdout_redirector->pop();
        $self->get_stderr_redirector->pop();
    }
}


sub specialize_and_compile_wrapper {
    my ($self, $specialization_arglist) = @_;

    eval {
        $self->enter_status('SPECIALIZATION');
        my $respecialization_from = $self->analysis_id && $self->analysis->logic_name.'('.$self->analysis_id.')';
        $self->adaptor->specialize_new_worker( $self, $specialization_arglist ? @$specialization_arglist : () );
        my $specialization_to = $self->analysis->logic_name.'('.$self->analysis_id.')';
        if($respecialization_from) {
            my $msg = "respecializing from $respecialization_from to $specialization_to";
            $self->worker_say( $msg );
            $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self->dbID, $msg, 0 );
        } else {
            $self->worker_say( "specializing to $specialization_to" );
        }
        1;
    } or do {
        my $msg = $@;
        chomp $msg;
        $self->worker_say( "[re]specialization failed:\t$msg" );
        $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self->dbID, $msg, 1 );

        $self->cause_of_death('SEE_MSG') unless($self->cause_of_death());   # some specific causes could have been set prior to die "...";
    };

    if( !$self->cause_of_death() ) {
        eval {
            $self->enter_status('COMPILATION');
            my $runnable_object = $self->analysis->process or die "Unknown compilation error";
            $runnable_object->db( $self->adaptor->db );
            $runnable_object->worker( $self );
            $runnable_object->debug( $self->debug );
            $runnable_object->execute_writes( $self->execute_writes );

            $self->runnable_object( $runnable_object );
            $self->enter_status('READY');

            $self->adaptor->db->dbc->disconnect_when_inactive(0);
            1;
        } or do {
            my $msg = $@;
            $self->worker_say( "runnable '".$self->analysis->module."' compilation failed :\t$msg" );
            $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self->dbID, $msg, 1 );

            $self->cause_of_death('SEE_MSG') unless($self->cause_of_death());   # some specific causes could have been set prior to die "...";
        };
    }
}


sub run_one_batch {
    my ($self, $jobs) = @_;

    my $jobs_done_here = 0;

    my $accu_adaptor    = $self->adaptor->db->get_AccumulatorAdaptor;
    my $max_retry_count = $self->analysis->max_retry_count();  # a constant (as the Worker is already specialized by the Queen) needed later for retrying jobs

    $self->adaptor->check_in_worker( $self );
    $self->adaptor->safe_synchronize_AnalysisStats($self->analysis->stats);

    if($self->debug) {
        $self->worker_say( "Stats : ".$self->analysis->stats->toString );
        $self->worker_say( 'claimed '.scalar(@{$jobs}).' jobs to process' );
    }

    my $job_partial_timing;

    ONE_BATCH: while(my $job = shift @$jobs) {         # to make sure jobs go out of scope without undue delay
        $self->worker_say( $job->toString ) if($self->debug); 

        my $job_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
        $job_partial_timing = {};

        $self->start_job_output_redirection($job);  # switch logging into job's STDERR
        eval {  # capture any throw/die
            $job->incomplete(1);

            my $runnable_object = $self->runnable_object();

            $self->adaptor->db->dbc->query_count(0);
            $job_stopwatch->restart();

            $job->param_init(
                $runnable_object->strict_hash_format(),
                $runnable_object->param_defaults(),
                $self->adaptor->db->get_MetaContainer->get_param_hash(),
                $self->analysis->parameters(),
                $job->input_id(),
                $accu_adaptor->fetch_structures_for_job_id( $job->dbID ),   # FIXME: or should we pass in the original hash to be extended by pushing?
            );

            $self->worker_say( 'Job '.$job->dbID." unsubstituted_params= ".stringify($job->{'_unsubstituted_param_hash'}) ) if($self->debug());

            $runnable_object->input_job( $job );    # "take" the job
            $job_partial_timing = $runnable_object->life_cycle();
            $runnable_object->input_job( undef );   # release an extra reference to the job

            $job->incomplete(0);
        };
        my $msg_thrown          = $@;

        $job->runtime_msec( $job_stopwatch->get_elapsed );  # whether successful or not
        $job->query_count( $self->adaptor->db->dbc->query_count );

        my $job_id              = $job->dbID();
        my $job_completion_line = "Job $job_id : complete";

        if($msg_thrown) {   # record the message - whether it was a success or failure:
            my $job_status_at_the_moment = $job->status();
            my $action = $job->incomplete ? 'died' : 'exited';
            $job_completion_line = "Job $job_id : $action in status '$job_status_at_the_moment' for the following reason: $msg_thrown";
            $self->adaptor->db->get_LogMessageAdaptor()->store_job_message($job_id, $msg_thrown, $job->incomplete );
        }

        print STDERR "\n$job_completion_line\n" if($self->log_dir and ($self->debug or $job->incomplete));      # one copy goes to the job's STDERR
        $self->stop_job_output_redirection($job);                                                               # and then we switch back to worker's STDERR
        $self->worker_say( $job_completion_line );                                                              # one copy goes to the worker's STDERR

        if($job->incomplete) {
                # If the job specifically said what to do next, respect that last wish.
                # Otherwise follow the default behaviour set by the beekeeper in $worker:
                #
            my $may_retry = defined($job->transient_error) ? $job->transient_error : $self->retry_throwing_jobs;

            $job->adaptor->release_and_age_job( $job->dbID, $max_retry_count, $may_retry, $job->runtime_msec );

            if( $self->prev_job_error                # a bit of AI: if the previous job failed as well, it is LIKELY that we have contamination
             or $job->lethal_for_worker ) {          # trust the job's expert knowledge
                my $reason = $self->prev_job_error            ? 'two failed jobs in a row'
                           :                                    'suggested by job itself';
                $self->worker_say( "Job's error has contaminated the Worker ($reason), so the Worker will now die" );
                $self->cause_of_death('CONTAMINATED');
                last ONE_BATCH;
            }
        } else {    # job successfully completed:
            $self->more_work_done( $job_partial_timing );
            $jobs_done_here++;
            $job->update_status('DONE');

            if(my $semaphored_job_id = $job->semaphored_job_id) {
                my $dbc = $self->adaptor->db->dbc;
                $dbc->do( "SELECT 1 FROM job WHERE job_id=$semaphored_job_id FOR UPDATE" ) if($dbc->driver ne 'sqlite');

                $job->adaptor->decrease_semaphore_count_for_jobid( $semaphored_job_id );    # step-unblock the semaphore
            }

            if($job->lethal_for_worker) {
                $self->worker_say( "The Job, although complete, wants the Worker to die" );
                $self->cause_of_death('CONTAMINATED');
                last ONE_BATCH;
            }
        }

        $self->prev_job_error( $job->incomplete );
        $self->enter_status('READY');
    } # /while(my $job = shift @$jobs)

    return $jobs_done_here;
}


sub enter_status {
    my ($self, $status, $msg) = @_;

    $msg ||= ": $status";

    if($self->debug) {
        $self->worker_say( $msg );
    }

    $self->status( $status );
    $self->adaptor->check_in_worker( $self );
}


sub start_job_output_redirection {
    my ($self, $job) = @_;

    if(my $worker_log_dir = $self->log_dir) {
        $self->get_stdout_redirector->push( $job->stdout_file( $worker_log_dir . '/job_id_' . $job->dbID . '_' . $job->retry_count . '.out' ) );
        $self->get_stderr_redirector->push( $job->stderr_file( $worker_log_dir . '/job_id_' . $job->dbID . '_' . $job->retry_count . '.err' ) );

        if(my $job_adaptor = $job->adaptor) {
            $job_adaptor->store_out_files($job);
        }
    }
}


sub stop_job_output_redirection {
    my ($self, $job) = @_;

    if($self->log_dir) {
        $self->get_stdout_redirector->pop();
        $self->get_stderr_redirector->pop();

        my $force_cleanup = !($self->debug || $job->incomplete);

        if($force_cleanup or -z $job->stdout_file) {
            $self->worker_say( "Deleting '".$job->stdout_file."' file" );
            unlink $job->stdout_file;
            $job->stdout_file(undef);
        }
        if($force_cleanup or -z $job->stderr_file) {
            $self->worker_say( "Deleting '".$job->stderr_file."' file" );
            unlink $job->stderr_file;
            $job->stderr_file(undef);
        }

        if(my $job_adaptor = $job->adaptor) {
            $job_adaptor->store_out_files($job);
        }
    }
}


1;
