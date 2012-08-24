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
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Utils::RedirectStack;
use Bio::EnsEMBL::Hive::Utils ('dir_revhash');  # import dir_revhash

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );


sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

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


sub db {
  my $self = shift;
  $self->{'_db'} = shift if(@_);
  return $self->{'_db'};
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


=head2 analysis

  Arg [1] : (optional) Bio::EnsEMBL::Analysis $value
  Title   :   analysis
  Usage   :   $value = $self->analysis;
              $self->analysis($$analysis);
  Description: Get/Set analysis object of this Worker
  DefaultValue : undef
  Returntype : Bio::EnsEMBL::Analysis object

=cut

sub analysis {
  my $self = shift;
  my $analysis = shift;

  if(defined($analysis)) {
    throw("analysis arg must be a [Bio::EnsEMBL::Analysis] not a [$analysis]")
       unless($analysis->isa('Bio::EnsEMBL::Analysis'));
    $self->{'_analysis'} = $analysis;
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



=head2 job_limit

  Title   :   job_limit
  Arg [1] :   (optional) integer $value
  Usage   :   $value = $self->job_limit;
              $self->job_limit($new_value);
  Description: Defines the maximum number of jobs a worker can process 
               before it needs to die. A worker 'dies' when either the 
               'life_span' or 'job_limit' is exceeded.
  DefaultValue : undef (relies on life_span to limit life of worker)
  Returntype : integer scalar

=cut

sub job_limit {
  my $self=shift;
  $self->{'_job_limit'}=shift if(@_);
  return $self->{'_job_limit'};
}

sub work_done {
  my $self = shift @_;

  if(@_) {
    $self->{'work_done'} = shift @_;
  }
  return $self->{'work_done'} || 0;
}


sub more_work_done {
    my ($self, $job_partial_timing) = @_;

    $self->{'work_done'}++;

    while( my ($state, $partial_timing_in_state) = each %$job_partial_timing ) {
        $self->{'_interval_partial_timing'}{$state} += $partial_timing_in_state;
    }
}


sub next_batch_size {
    my $self = shift @_;

    my $batch_size = $self->analysis->stats->get_or_estimate_batch_size();

    if(my $job_limit = $self->job_limit()) {               # if job_limit is set, it may influence batch_size
        my $jobs_to_do = $job_limit - $self->work_done();
        if($jobs_to_do < $batch_size) {
            return $jobs_to_do;         # should return 0 when job_limit has been attained
        }
    }
    return $batch_size;
}


sub job_limit_reached {
    my $self = shift @_;

    if($self->job_limit and $self->work_done >= $self->job_limit) { 
        return $self->work_done;
    }
    return 0;
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


sub host {
  my( $self, $value ) = @_;
  $self->{'_host'} = $value if($value);
  return $self->{'_host'};
}

sub process_id {
  my( $self, $value ) = @_;
  $self->{'_ppid'} = $value if($value);
  return $self->{'_ppid'};
}

sub cause_of_death {
  my( $self, $value ) = @_;
  $self->{'_cause_of_death'} = $value if($value);
  return $self->{'_cause_of_death'};
}

sub status {
  my( $self, $value ) = @_;
  $self->{'_status'} = $value if($value);
  return $self->{'_status'};
}

sub born {
  my( $self, $value ) = @_;
  $self->{'_born'} = $value if($value);
  return $self->{'_born'};
}

sub died {
  my( $self, $value ) = @_;
  $self->{'_died'} = $value if($value);
  return $self->{'_died'};
}

sub last_check_in {
  my( $self, $value ) = @_;
  $self->{'_last_check_in'} = $value if($value);
  return $self->{'_last_check_in'};
}


sub runnable_object {
    my $self = shift @_;

    $self->{'_runnable_object'} = shift @_ if(@_);
    return $self->{'_runnable_object'};
}


# this is a setter/getter that defines default behaviour when a job throws: should it be retried or not?

sub retry_throwing_jobs {
    my $self = shift @_;

    $self->{'_retry_throwing_jobs'} = shift @_ if(@_);
    return defined($self->{'_retry_throwing_jobs'}) ? $self->{'_retry_throwing_jobs'} : 1;
}

sub compile_module_once {
    my $self = shift @_;

    $self->{'_compile_module_once'} = shift @_ if(@_);
    return $self->{'_compile_module_once'} ;
}

=head2 hive_output_dir

  Arg [1] : (optional) string directory path
  Title   :   hive_output_dir
  Usage   :   $hive_output_dir = $self->hive_output_dir;
              $self->hive_output_dir($hive_output_dir);
  Description: getter/setter for the directory where STDOUT and STRERR of the hive will be redirected to.
          If it is "true", each worker will create its own subdirectory in it
          where each job will have its own .out and .err files.
  Returntype : string

=cut

sub hive_output_dir {
    my $self = shift @_;

    $self->{'_hive_output_dir'} = shift @_ if(@_);
    return $self->{'_hive_output_dir'};
}

sub worker_output_dir {
    my $self = shift @_;

    if((my $worker_output_dir = $self->{'_worker_output_dir'}) and not @_) { # no need to set, just return:

        return $worker_output_dir;

    } else { # let's try to set first:
    
        if(@_) { # setter mode ignores hive_output_dir

            $worker_output_dir = shift @_;

        } elsif( my $hive_output_dir = $self->hive_output_dir ) {

            my $worker_id = $self->dbID;

            my $dir_revhash = dir_revhash($worker_id);
            $worker_output_dir = join('/', $hive_output_dir, dir_revhash($worker_id), 'worker_id_'.$worker_id );
        }

        if($worker_output_dir) { # will not attempt to create if set to false
            system("mkdir -p $worker_output_dir") && die "Could not create '$worker_output_dir' because: $!";
        }

        $self->{'_worker_output_dir'} = $worker_output_dir;
    }
    return $self->{'_worker_output_dir'};
}

sub get_stdout_redirector {
    my $self = shift;

    return $self->{_stdout_redirector} ||= Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDOUT);
}

sub get_stderr_redirector {
    my $self = shift;

    return $self->{_stderr_redirector} ||= Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDERR);
}


sub perform_cleanup {
  my $self = shift;
  $self->{'_perform_cleanup'} = shift if(@_);
  $self->{'_perform_cleanup'} = 1 unless(defined($self->{'_perform_cleanup'}));
  return $self->{'_perform_cleanup'};
}

sub print_worker {
    my $self = shift;

    print $self->toString()."\n";
    print("\tbatch_size = ", $self->analysis->stats->get_or_estimate_batch_size(),"\n");
    print("\tjob_limit  = ", $self->job_limit,"\n") if(defined($self->job_limit));
    print("\tlife_span  = ", $self->life_span,"\n") if(defined($self->life_span));
    if(my $worker_output_dir = $self->worker_output_dir) {
        print("\tworker_output_dir = $worker_output_dir\n");
    } else {
        print("\tworker_output_dir = STDOUT/STDERR\n");
    }
}


sub toString {
    my $self = shift @_;

    return "Worker:\t".join(', ',
            'analysis='.$self->analysis->logic_name.'('.$self->analysis->dbID.')',
            'meadow='.$self->meadow_type.'/'.$self->meadow_name,
            'process='.$self->process_id.'@'.$self->host,
            'last_check_in='.$self->last_check_in,
    );
}


sub cleanup_worker_process_temp_directory {
  my $self = shift;
  if($self->{'_tmp_dir'} and (-e $self->{'_tmp_dir'}) ) {
    my $cmd = "rm -r ". $self->{'_tmp_dir'};
    system($cmd);
  }
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
    my $self = shift;

    $self->print_worker();
    if( my $worker_output_dir = $self->worker_output_dir ) {
        $self->get_stdout_redirector->push( $worker_output_dir.'/worker.out' );
        $self->get_stderr_redirector->push( $worker_output_dir.'/worker.err' );
        $self->print_worker();
    }

    if( $self->compile_module_once() ) {
        $self->enter_status('COMPILATION');
        my $runnable_object = $self->analysis->process or die "Unknown compilation error";
        $runnable_object->db( $self->db );
        $runnable_object->worker( $self );
        $runnable_object->debug( $self->debug );
        $runnable_object->execute_writes( $self->execute_writes );

        $self->runnable_object( $runnable_object );
        $self->enter_status('READY');
    }

  $self->db->dbc->disconnect_when_inactive(0);

  my $min_batch_time    = $self->analysis->stats->min_batch_time();
  my $job_adaptor       = $self->db->get_AnalysisJobAdaptor;

  do { # Worker's lifespan loop (ends only when the worker dies)
    my $batches_stopwatch           = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart();
    my $jobs_done_by_batches_loop   = 0; # by all iterations of internal loop
    $self->{'_interval_partial_timing'} = {};

    if( my $specific_job = $self->_specific_job() ) {
        $jobs_done_by_batches_loop += $self->run_one_batch( $job_adaptor->reclaim_job_for_worker($self, $specific_job) );
        $self->cause_of_death('JOB_LIMIT'); 
    } else {    # a proper "BATCHES" loop

        while (!$self->cause_of_death and $batches_stopwatch->get_elapsed < $min_batch_time) {

            if( scalar(@{ $job_adaptor->fetch_all_incomplete_jobs_by_worker_id( $self->dbID ) }) ) {
                my $msg = "Lost control. Check your Runnable for loose 'next' statements that are not part of a loop";
                warn "$msg";
                $self->cause_of_death('CONTAMINATED'); 
                $job_adaptor->release_undone_jobs_from_worker($self, $msg);
            } else {
                if(my $how_many_this_batch = $self->next_batch_size()) {
                    $jobs_done_by_batches_loop += $self->run_one_batch( $job_adaptor->grab_jobs_for_worker( $self, $how_many_this_batch ) );
                }

                if( my $jobs_completed = $self->job_limit_reached()) {
                    print "job_limit reached ($jobs_completed jobs completed)\n";
                    $self->cause_of_death('JOB_LIMIT'); 
                } elsif ( my $alive_for_secs = $self->life_span_limit_reached()) {
                    print "life_span limit reached (alive for $alive_for_secs secs)\n";
                    $self->cause_of_death('LIFESPAN'); 
                }
            }
        }
    }

        # The following two database-updating operations are resource-expensive (all workers hammering the same database+tables),
        # so they are not allowed to happen too frequently (not before $min_batch_time of work has been done)
        #
    if($jobs_done_by_batches_loop) {

        $self->db->get_AnalysisStatsAdaptor->interval_update_work_done(
            $self->analysis->dbID,
            $jobs_done_by_batches_loop,
            $batches_stopwatch->get_elapsed,
            $self->{'_interval_partial_timing'}{'FETCH_INPUT'}  || 0,
            $self->{'_interval_partial_timing'}{'RUN'}          || 0,
            $self->{'_interval_partial_timing'}{'WRITE_OUTPUT'} || 0,
        );
    }

    if (!$self->cause_of_death
    and 0 <= $self->analysis->stats->hive_capacity
    and $self->analysis->stats->hive_capacity < $self->analysis->stats->num_running_workers
    ) {
        $self->cause_of_death('HIVE_OVERLOAD');
    }

  } while (!$self->cause_of_death); # /Worker's lifespan loop

        # have runnable clean up any global/process files/data it may have created
    if($self->perform_cleanup) {
        if(my $runnable_object = $self->runnable_object()) {    # if -compile_module_once is 1, keep _tmp_dir in the Process object:
            $runnable_object->cleanup_worker_temp_directory();
        } else {                                                # otherwise keep _tmp_dir in the Worker object, so it needs its own cleanup method:
            $self->cleanup_worker_process_temp_directory();     #   TODO: remove this method when -compile_module_once becomes the only option
        }
    }

  $self->adaptor->register_worker_death($self);

  $self->analysis->stats->print_stats if($self->debug);

  printf("dbc %d disconnect cycles\n", $self->db->dbc->disconnect_count);
  print("total jobs completed : ", $self->work_done, "\n");
  
  if( $self->worker_output_dir() ) {
    $self->get_stdout_redirector->pop();
    $self->get_stderr_redirector->pop();
  }
}

sub run_one_batch {
    my ($self, $jobs) = @_;

    my $jobs_done_here = 0;

    my $max_retry_count = $self->analysis->stats->max_retry_count();  # a constant (as the Worker is already specialized by the Queen) needed later for retrying jobs

    $self->adaptor->check_in_worker( $self );
    $self->adaptor->safe_synchronize_AnalysisStats($self->analysis->stats);

    $self->cause_of_death('NO_WORK') unless(scalar @{$jobs});

    if($self->debug) {
        $self->analysis->stats->print_stats;
        print "claimed ".scalar(@{$jobs})." jobs to process\n";
    }

    my $job_partial_timing;

    while(my $job = shift @$jobs) {         # to make sure jobs go out of scope without undue delay
        $job->print_job if($self->debug); 

        my $job_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
        $job_partial_timing = {};

        $self->start_job_output_redirection($job);  # switch logging into job's STDERR
        eval {  # capture any throw/die
            $job->incomplete(1);

            my $runnable_object;

            if( $self->compile_module_once() ) {
                $runnable_object = $self->runnable_object();
            } else {
                $self->enter_status('COMPILATION', $job);
                $runnable_object = $self->analysis->process or die "Unknown compilation error";
                $runnable_object->db( $self->db );
                $runnable_object->worker( $self );
                $runnable_object->debug( $self->debug );
                $runnable_object->execute_writes( $self->execute_writes );
            }

            $self->db->dbc->query_count(0);
            $job_stopwatch->restart();

            $job->param_init( $runnable_object->strict_hash_format(), $runnable_object->param_defaults(), $self->db->get_MetaContainer->get_param_hash(), $self->analysis->parameters(), $job->input_id() );

            $runnable_object->input_job( $job );    # "take" the job
            $job_partial_timing = $runnable_object->life_cycle();
            $runnable_object->input_job( undef );   # release an extra reference to the job

            $job->incomplete(0);
        };
        my $msg_thrown          = $@;

        $job->runtime_msec( $job_stopwatch->get_elapsed );  # whether successful or not
        $job->query_count( $self->db->dbc->query_count );

        my $job_id              = $job->dbID();
        my $job_completion_line = "\njob $job_id : complete\n";

        if($msg_thrown) {   # record the message - whether it was a success or failure:
            my $job_status_at_the_moment = $job->status();
            my $action = $job->incomplete ? 'died' : 'exited';
            $job_completion_line = "\njob $job_id : $action in status '$job_status_at_the_moment' for the following reason: $msg_thrown\n";
            $self->db->get_JobMessageAdaptor()->register_message($job_id, $msg_thrown, $job->incomplete );
        }

        print STDERR $job_completion_line if($self->worker_output_dir and ($self->debug or $job->incomplete));  # one copy goes to the job's STDERR
        $self->stop_job_output_redirection($job);                                                               # and then we switch back to worker's STDERR
        print STDERR $job_completion_line;                                                                      # one copy goes to the worker's STDERR

        if($job->incomplete) {
                # If the job specifically said what to do next, respect that last wish.
                # Otherwise follow the default behaviour set by the beekeeper in $worker:
                #
            my $may_retry = defined($job->transient_error) ? $job->transient_error : $self->retry_throwing_jobs;

            $job->adaptor->release_and_age_job( $job->dbID, $max_retry_count, $may_retry );

            if($self->status eq 'COMPILATION'       # if it failed to compile, there is no point in continuing as the code WILL be broken
            or $self->prev_job_error                # a bit of AI: if the previous job failed as well, it is LIKELY that we have contamination
            or $job->lethal_for_worker ) {          # trust the job's expert knowledge
                my $reason = ($self->status eq 'COMPILATION') ? 'compilation error'
                           : $self->prev_job_error            ? 'two failed jobs in a row'
                           :                                    'suggested by job itself';
                warn "Job's error has contaminated the Worker ($reason), so the Worker will now die\n";
                $self->cause_of_death('CONTAMINATED');
                return $jobs_done_here;
            }
        } else {    # job successfully completed:
            $self->more_work_done( $job_partial_timing );
            $jobs_done_here++;
            $job->update_status('DONE');

            if(my $semaphored_job_id = $job->semaphored_job_id) {
                $job->adaptor->decrease_semaphore_count_for_jobid( $semaphored_job_id );    # step-unblock the semaphore
            }
        }

        $self->prev_job_error( $job->incomplete );
        $self->enter_status('READY');
    } # /while(my $job = shift @$jobs)

    return $jobs_done_here;
}


sub enter_status {
    my ($self, $status, $job) = @_;

    if($self->debug) {
        print STDERR "\n". ($job ? 'job '.$job->dbID : 'worker'). " : $status\n";
    }

    if($job) {
        $job->update_status( $status );
    }
    $self->status( $status );
    $self->adaptor->check_in_worker( $self );
}


sub start_job_output_redirection {
    my ($self, $job, $worker_output_dir) = @_;

    if(my $worker_output_dir = $self->worker_output_dir) {
        $self->get_stdout_redirector->push( $job->stdout_file( $worker_output_dir . '/job_id_' . $job->dbID . '_' . $job->retry_count . '.out' ) );
        $self->get_stderr_redirector->push( $job->stderr_file( $worker_output_dir . '/job_id_' . $job->dbID . '_' . $job->retry_count . '.err' ) );

        if(my $job_adaptor = $job->adaptor) {
            $job_adaptor->store_out_files($job);
        }
    }
}


sub stop_job_output_redirection {
    my ($self, $job) = @_;

    if($self->worker_output_dir) {
        $self->get_stdout_redirector->pop();
        $self->get_stderr_redirector->pop();

        my $force_cleanup = !($self->debug || $job->incomplete);

        if($force_cleanup or -z $job->stdout_file) {
            warn "Deleting '".$job->stdout_file."' file\n";
            unlink $job->stdout_file;
            $job->stdout_file(undef);
        }
        if($force_cleanup or -z $job->stderr_file) {
            warn "Deleting '".$job->stderr_file."' file\n";
            unlink $job->stderr_file;
            $job->stderr_file(undef);
        }

        if(my $job_adaptor = $job->adaptor) {
            $job_adaptor->store_out_files($job);
        }
    }
}


sub _specific_job {
  my $self = shift;
  $self->{'_specific_job'} = shift if(@_);
  return $self->{'_specific_job'};
}

1;
