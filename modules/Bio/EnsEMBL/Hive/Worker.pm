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
  work, creates the next layer of analysis_job entries by interfacing to
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
  analyses by querying the analysis_jobs, summarizing, and updating the
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
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;
use POSIX;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Hive::Process;

use Bio::EnsEMBL::Hive::Utils ('dir_revhash');  # import dir_revhash

## Minimum amount of time in msec that a worker should run before reporting
## back to the hive. This is used when setting the batch_size automatically.
## 120000 msec = 2 minutes
my $MIN_BATCH_TIME = 2*60*1000;

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  return $self;
}

sub init {
  my $self = shift;

  my $lifespan_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
  $lifespan_stopwatch->_unit(1); # count in seconds (default is milliseconds)
  $lifespan_stopwatch->restart;
  $self->lifespan_stopwatch( $lifespan_stopwatch );

  $self->debug(0);
  return $self;
}

sub queen {
  my $self = shift;
  $self->{'_queen'} = shift if(@_);
  return $self->{'_queen'};
}
sub db {
  my $self = shift;
  $self->{'_db'} = shift if(@_);
  return $self->{'_db'};
}
sub beekeeper {
  my $self = shift;
  $self->{'_beekeeper'} = shift if(@_);
  return $self->{'_beekeeper'};
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
  my $self = shift @_;

  $self->{'work_done'}++;
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


sub worker_id {
  my( $self, $value ) = @_;
  $self->{'_worker_id'} = $value if($value);
  return $self->{'_worker_id'};
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

# this is a setter/getter that defines default behaviour when a job throws: should it be retried or not?

sub retry_throwing_jobs {
    my $self = shift @_;

    $self->{'_retry_throwing_jobs'} = shift @_ if(@_);
    return defined($self->{'_retry_throwing_jobs'}) ? $self->{'_retry_throwing_jobs'} : 1;
}

=head2 hive_output_dir

  Arg [1] : (optional) string directory path
  Title   :   hive_output_dir
  Usage   :   $hive_output_dir = $self->hive_output_dir;
              $self->hive_output_dir($hive_output_dir);
  Description: getter/setter for the directory where STDOUT and STRERR of the hive will be redirected to.
          If it is "true", each worker will create its own subdirectory in it
          where each analysis_job will have its own .out and .err files.
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

            my $worker_id = $self->worker_id();

            $worker_output_dir = join('/', $hive_output_dir, dir_revhash($worker_id), 'worker_id_'.$worker_id );
        }

        if($worker_output_dir) { # will not attempt to create if set to false
            system("mkdir -p $worker_output_dir") && die "Could not create '$worker_output_dir' because: $!";
        }

        $self->{'_worker_output_dir'} = $worker_output_dir;
    }
    return $self->{'_worker_output_dir'};
}


sub perform_cleanup {
  my $self = shift;
  $self->{'_perform_cleanup'} = shift if(@_);
  $self->{'_perform_cleanup'} = 1 unless(defined($self->{'_perform_cleanup'}));
  return $self->{'_perform_cleanup'};
}

sub print_worker {
  my $self = shift;
  print("WORKER: worker_id=",$self->worker_id,
     " analysis_id=(",$self->analysis->dbID,")",$self->analysis->logic_name,
     " host=",$self->host,
     " pid=",$self->process_id,
     "\n");
  print("  batch_size = ", $self->batch_size,"\n");
  print("  job_limit  = ", $self->job_limit,"\n") if(defined($self->job_limit));
  print("  life_span  = ", $self->life_span,"\n") if(defined($self->life_span));
  if(my $worker_output_dir = $self->worker_output_dir) {
    print("  worker_output_dir = $worker_output_dir\n");
  } else {
    print("  worker_output_dir = STDOUT/STDERR\n");
  }
}


sub worker_process_temp_directory {
  my $self = shift;
  
  unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
    #create temp directory to hold fasta databases
    my $username = $ENV{'USER'};
    my $worker_id = $self->worker_id();
    $self->{'_tmp_dir'} = "/tmp/worker_${username}.${worker_id}/";
    mkdir($self->{'_tmp_dir'}, 0777);
    throw("unable to create a writable directory ".$self->{'_tmp_dir'}) unless(-w $self->{'_tmp_dir'});
  }
  return $self->{'_tmp_dir'};
}


sub cleanup_worker_process_temp_directory {
  my $self = shift;
  if($self->{'_tmp_dir'}) {
    my $cmd = "rm -r ". $self->{'_tmp_dir'};
    system($cmd);
  }
}

###############################
#
# WORK section
#
###############################

=head2 batch_size

  Args    :   none
  Title   :   batch_size
  Usage   :   $value = $self->batch_size;
              $self->batch_size($new_value);
  Description: Defines the number of jobs that should run in batch
               before querying the database for the next job batch.  Used by the
               Hive system to manage the number of workers needed to complete a
               particular job type.
  DefaultValue : batch_size of analysis
  Returntype : integer scalar

=cut

sub set_worker_batch_size {
  my $self = shift;
  my $batch_size = shift;
  if(defined($batch_size)) {
    $self->{'_batch_size'} = $batch_size;
  }
}

sub batch_size {
  my $self = shift;

  my $stats = $self->analysis->stats;
  my $batch_size = $stats->batch_size;
  if(defined($self->{'_batch_size'})) {
    $batch_size = $self->{'_batch_size'};
  } 
    
  if(($batch_size <= 0) and ($stats->avg_msec_per_job)) {
    $batch_size = POSIX::ceil($MIN_BATCH_TIME / $stats->avg_msec_per_job); # num jobs in $MIN_BATCH_TIME msecs
  }
  $batch_size = 1 if($batch_size < 1); # make sure we grab at least one job
  
  if($self->job_limit and ($self->job_limit < $batch_size)) {
    $batch_size = $self->job_limit;
  }
  return $batch_size;
}


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
      3) updating the analysis_job, analysis_stats, and hive tables to track the 
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
    open OLDOUT, ">&STDOUT";
    open OLDERR, ">&STDERR";
    open WORKER_STDOUT, ">${worker_output_dir}/worker.out";
    open WORKER_STDERR, ">${worker_output_dir}/worker.err";
    close STDOUT;
    close STDERR;
    open STDOUT, ">&WORKER_STDOUT";
    open STDERR, ">&WORKER_STDERR";
    $self->print_worker();
  }

  $self->db->dbc->disconnect_when_inactive(0);

  my $job_adaptor = $self->db->get_AnalysisJobAdaptor;

  do { # Worker's lifespan loop (ends only when the worker dies)
    my $batches_stopwatch           = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart();
    $self->{'fetching_stopwatch'}   = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    $self->{'running_stopwatch'}    = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    $self->{'writing_stopwatch'}    = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my $jobs_done_by_batches_loop   = 0; # by all iterations of internal loop

    if( my $specific_job = $self->_specific_job() ) {
        $jobs_done_by_batches_loop += $self->run_one_batch( [ $self->queen->worker_reclaim_job($self, $specific_job) ] );
        $self->cause_of_death('JOB_LIMIT'); 
    } else {    # a proper "BATCHES" loop

        while (!$self->cause_of_death and $batches_stopwatch->get_elapsed < $MIN_BATCH_TIME) {

            if(my $incompleted_count = @{ $job_adaptor->fetch_all_incomplete_jobs_by_worker_id( $self->worker_id ) }) {
                die "This worker is too greedy: not having completed $incompleted_count jobs it is trying to grab yet more jobs! Has it gone multithreaded?\n";
            } else {
                $jobs_done_by_batches_loop += $self->run_one_batch( $job_adaptor->grab_jobs_for_worker( $self ) );

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
        # so they are not allowed to happen too frequently (not before $MIN_BATCH_TIME of work has been done)
        #
    $self->db->get_AnalysisStatsAdaptor->interval_update_work_done(
        $self->analysis->dbID,
        $jobs_done_by_batches_loop,
        $batches_stopwatch->get_elapsed,
        $self->{'fetching_stopwatch'}->get_elapsed,
        $self->{'running_stopwatch'}->get_elapsed,
        $self->{'writing_stopwatch'}->get_elapsed,
    );

    if (!$self->cause_of_death
    and $self->analysis->stats->hive_capacity >= 0
    and $self->analysis->stats->num_running_workers > $self->analysis->stats->hive_capacity
    and $self->analysis->stats->adaptor->decrease_running_workers_on_hive_overload( $self->analysis->dbID ) # careful with order, this operation has side-effect
    ) {
        $self->cause_of_death('HIVE_OVERLOAD');
    }
  } while (!$self->cause_of_death); # /Worker's lifespan loop

  if($self->perform_cleanup) {
    #have runnable cleanup any global/process files/data it may have created
    $self->cleanup_worker_process_temp_directory;
  }

  $self->queen->register_worker_death($self);

  $self->analysis->stats->print_stats if($self->debug);

  printf("dbc %d disconnect cycles\n", $self->db->dbc->disconnect_count);
  print("total jobs completed : ", $self->work_done, "\n");
  
  if( $self->worker_output_dir() ) {
    close STDOUT;
    close STDERR;
    close WORKER_STDOUT;
    close WORKER_STDERR;
    open STDOUT, ">&", \*OLDOUT;
    open STDERR, ">&", \*OLDERR;
  }
}

sub run_one_batch {
    my ($self, $jobs) = @_;

    my $jobs_done_here = 0;

    my $max_retry_count = $self->analysis->stats->max_retry_count();  # a constant (as the Worker is already specialized by the Queen) needed later for retrying jobs

    $self->queen->worker_check_in($self); #will sync analysis_stats if needed

    $self->cause_of_death('NO_WORK') unless(scalar @{$jobs});

    if($self->debug) {
        $self->analysis->stats->print_stats;
        print(STDOUT "claimed ",scalar(@{$jobs}), " jobs to process\n");
    }

    foreach my $job (@{$jobs}) {
        $job->print_job if($self->debug); 

        $self->start_job_output_redirection($job);
        eval {  # capture any throw/die
            $self->run_module_with_job($job);
        };
        my $msg_thrown = $@;
        $self->stop_job_output_redirection($job);

        if($msg_thrown) {   # record the message - whether it was a success or failure:
            my $job_id                   = $job->dbID();
            my $job_status_at_the_moment = $job->status();
            warn "Job with id=$job_id died in status '$job_status_at_the_moment' for the following reason: $msg_thrown\n";
            $self->db()->get_JobMessageAdaptor()->register_message($job_id, $msg_thrown, $job->incomplete );
        }

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
                           : $self->prev_job_error           ? 'two failed jobs in a row'
                           :                                   'suggested by job itself';
                warn "Job's error has contaminated the Worker ($reason), so the Worker will now die\n";
                $self->cause_of_death('CONTAMINATED');
                return $jobs_done_here;
            }
        } else {    # job successfully completed:

            if(my $semaphored_job_id = $job->semaphored_job_id) {
                $job->adaptor->decrease_semaphore_count_for_jobid( $semaphored_job_id );    # step-unblock the semaphore
            }
            $self->more_work_done;
            $jobs_done_here++;
            $job->update_status('DONE');
        }

        $self->prev_job_error( $job->incomplete );
        $self->enter_status('READY');
    }

    return $jobs_done_here;
}


sub run_module_with_job {
  my ($self, $job) = @_;

  $job->incomplete(1);
  $job->autoflow(1);

  $self->enter_status('COMPILATION');
  $job->update_status('COMPILATION');
  my $runObj = $self->analysis->process or die "Unknown compilation error";
  
  my $job_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart();
  $self->queen->dbc->query_count(0);

  #pass the input_id from the job into the Process object
  if( $runObj->isa('Bio::EnsEMBL::Hive::Process') ) {
    $runObj->input_job($job);
    $runObj->queen($self->queen);
    $runObj->worker($self);
    $runObj->debug($self->debug);

    $job->param_init( $runObj->strict_hash_format(), $runObj->param_defaults(), $self->db->get_MetaContainer->get_param_hash(), $self->analysis->parameters(), $job->input_id() );

  } else {
    $runObj->input_id($job->input_id);
    $runObj->db($self->db);

    $job->param_init( 0, $self->db->get_MetaContainer->get_param_hash(), $self->analysis->parameters(), $job->input_id() ); # Well, why not?
  }

    $self->enter_status('GET_INPUT');
    $job->update_status('GET_INPUT');
    print("\nGET_INPUT\n") if($self->debug); 

    $self->{'fetching_stopwatch'}->continue();
    $runObj->fetch_input;
    $self->{'fetching_stopwatch'}->pause();

    $self->enter_status('RUN');
    $job->update_status('RUN');
    print("\nRUN\n") if($self->debug); 

    $self->{'running_stopwatch'}->continue();
    $runObj->run;
    $self->{'running_stopwatch'}->pause();

    if($self->execute_writes) {
        $self->enter_status('WRITE_OUTPUT');
        $job->update_status('WRITE_OUTPUT');
        print("\nWRITE_OUTPUT\n") if($self->debug); 

        $self->{'writing_stopwatch'}->continue();
        $runObj->write_output;
        $self->{'writing_stopwatch'}->pause();

        if( $job->autoflow ) {
            printf("AUTOFLOW input->output\n") if($self->debug);
            $job->dataflow_output_id();
        }
    } else {
        print("\n\n!!!! NOT write_output\n\n\n") if($self->debug); 
    }

    $job->query_count($self->queen->dbc->query_count);
    $job->runtime_msec( $job_stopwatch->get_elapsed );

    $job->incomplete(0);
}

sub enter_status {
  my ($self, $status) = @_;
  return $self->queen->enter_status($self, $status);
}

sub start_job_output_redirection {
    my $self = shift;
    my $job  = shift or return;

    my $job_adaptor = $job->adaptor or return;

    if( my $worker_output_dir = $self->worker_output_dir ) {

        $job->stdout_file( $worker_output_dir . '/job_id_' . $job->dbID . '.out' );
        $job->stderr_file( $worker_output_dir . '/job_id_' . $job->dbID . '.err' );

        close STDOUT;
        open STDOUT, ">".$job->stdout_file;

        close STDERR;
        open STDERR, ">".$job->stderr_file;

        $job_adaptor->store_out_files($job);
    }
}


sub stop_job_output_redirection {
    my $self = shift;
    my $job  = shift or return;

    my $job_adaptor = $job->adaptor or return;

    if( $self->worker_output_dir ) {

        # the following flushes $job->stderr_file and $job->stdout_file
        open STDOUT, ">&WORKER_STDOUT";
        open STDERR, ">&WORKER_STDERR";

        if(-z $job->stdout_file) {
            unlink $job->stdout_file;
            $job->stdout_file('');
        }
        if(-z $job->stderr_file) {
            unlink $job->stderr_file;
            $job->stderr_file('');
        }

        $job_adaptor->store_out_files($job);
    }
}

sub _specific_job {
  my $self = shift;
  $self->{'_specific_job'} = shift if(@_);
  return $self->{'_specific_job'};
}

1;
