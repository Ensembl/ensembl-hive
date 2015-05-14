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


package Bio::EnsEMBL::Hive::Worker;

use strict;
use warnings;
use POSIX;

use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Limiter;
use Bio::EnsEMBL::Hive::Utils::RedirectStack;
use Bio::EnsEMBL::Hive::Utils::Stopwatch;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'throw');

use base ( 'Bio::EnsEMBL::Hive::Storable' );


=head1 AUTOLOADED

    resource_class_id / resource_class

=cut


sub init {
    my $self = shift;

    my $lifespan_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    $lifespan_stopwatch->_unit(1); # count in seconds (default is milliseconds)
    $lifespan_stopwatch->restart;
    $self->lifespan_stopwatch( $lifespan_stopwatch );

    return $self;
}


## Storable object's getters/setters:


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


sub meadow_host {
    my $self = shift;
    $self->{'_meadow_host'} = shift if(@_);
    return $self->{'_meadow_host'};
}


sub meadow_user {
    my $self = shift;
    $self->{'_meadow_user'} = shift if(@_);
    return $self->{'_meadow_user'};
}


sub process_id {
    my $self = shift;
    $self->{'_process_id'} = shift if(@_);
    return $self->{'_process_id'};
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


sub when_born {
    my $self = shift;
    $self->{'_when_born'} = shift if(@_);
    return $self->{'_when_born'};
}


sub when_checked_in {
    my $self = shift;
    $self->{'_when_checked_in'} = shift if(@_);
    return $self->{'_when_checked_in'};
}


sub when_seen {
    my $self = shift;
    $self->{'_when_seen'} = shift if(@_);
    return $self->{'_when_seen'};
}


sub when_died {
    my $self = shift;
    $self->{'_when_died'} = shift if(@_);
    return $self->{'_when_died'};
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

sub current_role {
    my $self = shift;

    if( @_ ) {
        if( my $from_analysis = $self->{'_current_role'} && $self->{'_current_role'}->analysis ) {
            $self->worker_say( "unspecializing from ".$from_analysis->logic_name.'('.$from_analysis->dbID.')' );
        }
        my $new_role = shift @_;
        if( my $to_analysis = $new_role && $new_role->analysis ) {
            $self->worker_say( "specializing to ".$to_analysis->logic_name.'('.$to_analysis->dbID.')' );
        }
        $self->{'_current_role'} = $new_role;
    }
    return $self->{'_current_role'};
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

    my $worker_id       = $self->dbID();
    my $current_role    = $self->current_role;
    my $job_id          = $self->runnable_object && $self->runnable_object->input_job && $self->runnable_object->input_job->dbID;
    print "Worker $worker_id [ ". ( $current_role
                                    ? ('Role '.$current_role->dbID.' , '.$current_role->analysis->logic_name.'('.$current_role->analysis_id.')'
                                        . ($job_id ? ", Job $job_id" : '')
                                      )
                                    : 'UNSPECIALIZED'
                                  )." ] $msg\n";
}


sub toString {
    my ($self, $include_analysis) = @_;

    my $current_role = $self->current_role;

    return join(', ',
            $include_analysis ? ( 'analysis='.($current_role ? $current_role->analysis->logic_name.'('.$current_role->analysis_id.')' : 'UNSPECIALIZED') ) : (),
            'resource_class_id='.($self->resource_class_id // 'NULL'),
            'meadow='.$self->meadow_type.'/'.$self->meadow_name,
            'process='.$self->meadow_user.'@'.$self->meadow_host.'#'.$self->process_id,
            'when_checked_in='.($self->when_checked_in // 'NEVER'),
            'batch_size='.($current_role ? $current_role->analysis->stats->get_or_estimate_batch_size() : 'UNSPECIALIZED'),
            'job_limit='.($self->job_limiter->available_capacity() // 'NONE'),
            'life_span='.($self->life_span // 'UNLIM'),
            'worker_log_dir='.($self->log_dir // 'STDOUT/STDERR'),
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
    my ($self, $specialization_arghash) = @_;

    if( my $worker_log_dir = $self->log_dir ) {
        $self->get_stdout_redirector->push( $worker_log_dir.'/worker.out' );
        $self->get_stderr_redirector->push( $worker_log_dir.'/worker.err' );
    }

    my $min_batch_time  = Bio::EnsEMBL::Hive::AnalysisStats::min_batch_time();
    my $job_adaptor     = $self->adaptor->db->get_AnalysisJobAdaptor;

    print "\n"; # to clear beekeeper's prompt in case output is not logged
    $self->worker_say( $self->toString() );
    $self->specialize_and_compile_wrapper( $specialization_arghash );

    while (!$self->cause_of_death) {  # Worker's lifespan loop (ends only when the worker dies for any reason)

        my $batches_stopwatch           = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart();
        my $jobs_done_by_batches_loop   = 0; # by all iterations of internal loop
        $self->{'_interval_partial_timing'} = {};

        if( my $special_batch = $self->special_batch() ) {
            my $special_batch_length = scalar(@$special_batch);     # has to be recorded because the list is gradually destroyed
            $jobs_done_by_batches_loop += $self->run_one_batch( $special_batch, $special_batch_length );
            $self->cause_of_death( $jobs_done_by_batches_loop == $special_batch_length ? 'JOB_LIMIT' : 'CONTAMINATED');
        } else {    # a proper "BATCHES" loop

            while (!$self->cause_of_death and $batches_stopwatch->get_elapsed < $min_batch_time) {
                my $current_role        = $self->current_role;

                if( scalar(@{ $job_adaptor->fetch_all_incomplete_jobs_by_role_id( $current_role->dbID ) }) ) {
                    my $msg = "Lost control. Check your Runnable for loose 'next' statements that are not part of a loop";
                    $self->worker_say( $msg );
                    $self->cause_of_death('CONTAMINATED');
                    $job_adaptor->release_undone_jobs_from_role($current_role, $msg);

                } elsif( $self->job_limiter->reached()) {
                    $self->worker_say( "job_limit reached (".$self->work_done." jobs completed)" );
                    $self->cause_of_death('JOB_LIMIT');

                } elsif ( my $alive_for_secs = $self->life_span_limit_reached()) {
                    $self->worker_say( "life_span limit reached (alive for $alive_for_secs secs)" );
                    $self->cause_of_death('LIFESPAN');

                } else {
                    my $stats = $current_role->analysis->stats;
                    my $desired_batch_size  = $stats->get_or_estimate_batch_size();
                    my $hit_the_limit;  # dummy at the moment
                    ($desired_batch_size, $hit_the_limit)   = $self->job_limiter->preliminary_offer( $desired_batch_size );

                    my $actual_batch = $job_adaptor->grab_jobs_for_role( $current_role, $desired_batch_size );

                    if($self->debug) {
                        $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self,
                             "Claiming: ready_job_count=".$stats->ready_job_count
                            .", num_running_workers=".$stats->num_running_workers
                            .", desired_batch_size=$desired_batch_size, actual_batch_size=".scalar(@$actual_batch),
                        0 );
                    }

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
                $self->current_role->analysis->dbID,
                $jobs_done_by_batches_loop,
                $batches_stopwatch->get_elapsed,
                $self->{'_interval_partial_timing'}{'FETCH_INPUT'}  || 0,
                $self->{'_interval_partial_timing'}{'RUN'}          || 0,
                $self->{'_interval_partial_timing'}{'WRITE_OUTPUT'} || 0,
            );
        }

            # A mechanism whereby workers can be caused to exit even if they were doing fine:
        if (!$self->cause_of_death) {
            my $analysis = $self->current_role->analysis;
            my $stats = $analysis->stats;     # make sure it is fresh from the DB
            if( defined($stats->hive_capacity) && (0 <= $stats->hive_capacity) && ($self->adaptor->db->get_RoleAdaptor->get_hive_current_load >= 1.1)
             or defined($analysis->analysis_capacity) && (0 <= $analysis->analysis_capacity) && ($analysis->analysis_capacity < $stats->num_running_workers)
            ) {
                $self->cause_of_death('HIVE_OVERLOAD');
            }
        }

        my $cod = $self->cause_of_death() || '';

        if( $cod eq 'NO_WORK') {
            $self->adaptor->db->get_AnalysisStatsAdaptor->update_status( $self->current_role->analysis_id, 'ALL_CLAIMED' );
        }

        if( $cod =~ /^(NO_WORK|HIVE_OVERLOAD)$/ and $self->can_respecialize and (!$specialization_arghash->{'-analyses_pattern'} or $specialization_arghash->{'-analyses_pattern'}!~/^\w+$/) ) {
            my $old_role = $self->current_role;
            $self->adaptor->db->get_RoleAdaptor->finalize_role( $old_role, 0 );
            $self->current_role( undef );
            $self->cause_of_death(undef);
            $self->specialize_and_compile_wrapper( $specialization_arghash, $old_role->analysis );
        }

    }     # /Worker's lifespan loop

        # have runnable clean up any global/process files/data it may have created
    if($self->perform_cleanup) {
        if(my $runnable_object = $self->runnable_object) {    # the temp_directory is actually kept in the Process object:
            $runnable_object->cleanup_worker_temp_directory();
        }
    }

    # The second argument ("update_when_checked_in") is set to force an
    # update of the "when_checked_in" timestamp in the worker table
    $self->adaptor->register_worker_death($self, 1);

    if($self->debug) {
        $self->worker_say( 'AnalysisStats : '.$self->current_role->analysis->stats->toString ) if( $self->current_role );
        $self->worker_say( 'dbc '.$self->adaptor->db->dbc->disconnect_count. ' disconnect cycles' );
    }

    $self->worker_say( "Having completed ".$self->work_done." jobs the Worker exits : ".$self->cause_of_death  );

    if( $self->log_dir ) {
        $self->get_stdout_redirector->pop();
        $self->get_stderr_redirector->pop();
    }
}


sub specialize_and_compile_wrapper {
    my ($self, $specialization_arghash, $prev_analysis) = @_;

    eval {
        $self->enter_status('SPECIALIZATION');
        $self->adaptor->specialize_worker( $self, $specialization_arghash );
        1;
    } or do {
        my $msg = $@;
        chomp $msg;
        $self->worker_say( "specialization failed:\t$msg" );

        $self->cause_of_death('SEE_MSG') unless($self->cause_of_death());   # some specific causes could have been set prior to die "...";

        my $is_error = $self->cause_of_death() ne 'NO_ROLE';
        $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self, $msg, $is_error );
    };

    if( !$self->cause_of_death() ) {
        eval {
            $self->enter_status('COMPILATION');

            my $runnable_object = $self->current_role->analysis->get_compiled_module_name->new($self->current_role->analysis->language, $self->current_role->analysis->module)  # Only GuestProcess will read the arguments
                or die "Unknown compilation error";

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
            $self->worker_say( "runnable '".$self->current_role->analysis->module."' compilation failed :\t$msg" );
            $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self, $msg, 1 );

            $self->cause_of_death('SEE_MSG') unless($self->cause_of_death());   # some specific causes could have been set prior to die "...";
        };
    }
}


sub run_one_batch {
    my ($self, $jobs, $is_special_batch) = @_;

    my $jobs_done_here = 0;

    my $current_role            = $self->current_role;
    my $max_retry_count         = $current_role->analysis->max_retry_count();  # a constant (as the Worker is already specialized by the Queen) needed later for retrying jobs
    my $stats                   = $current_role->analysis->stats;   # cache it to avoid reloading

    $self->adaptor->check_in_worker( $self );
    $self->adaptor->safe_synchronize_AnalysisStats( $stats );

    if($self->debug) {
        $self->worker_say( 'AnalysisStats : ' . $stats->toString );
        $self->worker_say( 'claimed '.scalar(@{$jobs}).' jobs to process' );
    }

    my $job_partial_timing;

    ONE_BATCH: while(my $job = shift @$jobs) {         # to make sure jobs go out of scope without undue delay

        my $job_id = $job->dbID();
        $self->worker_say( $job->toString ) if($self->debug); 

        my $job_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
        $job_partial_timing = {};

        $self->start_job_output_redirection($job);  # switch logging into job's STDERR
        eval {  # capture any throw/die

            $job->incomplete(1);
            $self->adaptor->db->dbc->query_count(0);
            $job_stopwatch->restart();

            $job->analysis( $current_role->analysis );

            my $runnable_object = $self->runnable_object();
            $job->load_parameters( $runnable_object );

            $self->worker_say( "Job $job_id unsubstituted_params= ".stringify($job->{'_unsubstituted_param_hash'}) ) if($self->debug());

            $runnable_object->input_job( $job );    # "take" the job
            $job_partial_timing = $runnable_object->life_cycle();
        };
        if(my $msg = $@) {
            $job->died_somewhere( $job->incomplete );  # it will be OR'd inside
            $self->runnable_object->warning( $msg, $job->incomplete );
        }

            # whether the job completed successfully or not:
        $self->runnable_object->input_job( undef );   # release an extra reference to the job
        $job->runtime_msec( $job_stopwatch->get_elapsed );
        $job->query_count( $self->adaptor->db->dbc->query_count );

        my $job_completion_line = "Job $job_id : ". ($job->died_somewhere ? 'died' : 'complete' );

        print STDERR "\n$job_completion_line\n" if($self->log_dir and ($self->debug or $job->died_somewhere));  # one copy goes to the job's STDERR
        $self->stop_job_output_redirection($job);                                                               # and then we switch back to worker's STDERR
        $self->worker_say( $job_completion_line );                                                              # one copy goes to the worker's STDERR

        $self->current_role->register_attempt( ! $job->died_somewhere );

        if($job->died_somewhere) {
                # If the job specifically said what to do next, respect that last wish.
                # Otherwise follow the default behaviour set by the beekeeper in $worker:
                #
            my $may_retry = defined($job->transient_error) ? $job->transient_error : $self->retry_throwing_jobs;

            $job->adaptor->release_and_age_job( $job_id, $max_retry_count, $may_retry, $job->runtime_msec );

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
            $job->set_and_update_status('DONE');

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

        $self->prev_job_error( $job->died_somewhere );
        $self->enter_status('READY');

        my $refresh_tolerance_seconds = 20;

            # UNCLAIM THE SURPLUS:
        my $remaining_jobs_in_batch = scalar(@$jobs);
        if( !$is_special_batch and $remaining_jobs_in_batch and $stats->refresh( $refresh_tolerance_seconds ) ) { # if we DID refresh
            my $ready_job_count = $stats->ready_job_count;
            my $optimal_batch_now = $stats->get_or_estimate_batch_size( $remaining_jobs_in_batch );
            my $jobs_to_unclaim = $remaining_jobs_in_batch - $optimal_batch_now;
            $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self, "Check-point: rdy=$ready_job_count, rem=$remaining_jobs_in_batch, opt=$optimal_batch_now, 2unc=$jobs_to_unclaim", 0 );
            if( $jobs_to_unclaim > 0 ) {
                # FIXME: a faster way would be to unclaim( splice(@$jobs, -$jobs_to_unclaim) );  # unclaim the last $jobs_to_unclaim elements
                    # currently we just dump all the remaining jobs and prepare to take a fresh batch:
                $job->adaptor->release_claimed_jobs_from_role( $current_role );
                $jobs = [];
                $self->adaptor->db->get_LogMessageAdaptor()->store_worker_message($self, "Unclaimed $jobs_to_unclaim jobs (trimming the tail)", 0 );
            }
        }

    } # /while(my $job = shift @$jobs)

    return $jobs_done_here;
}


sub set_and_update_status {
    my ($self, $status ) = @_;

    $self->status($status);

    if(my $adaptor = $self->adaptor) {
        $adaptor->check_in_worker( $self );
    }
}


sub enter_status {
    my ($self, $status) = @_;

    if($self->debug) {
        $self->worker_say( '-> '.$status );
    }

    $self->set_and_update_status( $status );
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

        my $force_cleanup = !($self->debug || $job->died_somewhere);

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
