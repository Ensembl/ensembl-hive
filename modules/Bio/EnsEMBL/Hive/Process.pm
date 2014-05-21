=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Process

=head1 DESCRIPTION

    Abstract superclass.  Each Process makes up the individual building blocks 
    of the system.  Instances of these processes are created in a hive workflow 
    graph of Analysis entries that are linked together with dataflow and 
    AnalysisCtrl rules.
  
    Instances of these Processes are created by the system as work is done.
    The newly created Process will have preset $self->db, $self->dbc, $self->input_id
    and several other variables. 
    From this input and configuration data, each Process can then proceed to 
    do something.  The flow of execution within a Process is:
        pre_cleanup() if($retry_count>0);   # clean up databases/filesystem before subsequent attempts
        fetch_input();                      # fetch the data from databases/filesystems
        run();                              # perform the main computation 
        write_output();                     # record the results in databases/filesystems
        post_healthcheck();                 # check if we got the expected result (optional)
        post_cleanup();                     # destroy all non-trivial data structures after the job is done
    The developer can implement their own versions of
    pre_cleanup, fetch_input, run, write_output, and post_cleanup to do what they need.  

    The entire system is based around the concept of a workflow graph which
    can split and loop back on itself.  This is accomplished by dataflow
    rules (similar to Unix pipes) that connect one Process (or analysis) to others.
    Where a Unix command line program can send output on STDOUT STDERR pipes, 
    a hive Process has access to unlimited pipes referenced by numerical 
    branch_codes. This is accomplished within the Process via 
    $self->dataflow_output_id(...);  
  
    The design philosophy is that each Process does its work and creates output, 
    but it doesn't worry about where the input came from, or where its output 
    goes. If the system has dataflow pipes connected, then the output jobs 
    have purpose, if not - the output work is thrown away.  The workflow graph 
    'controls' the behaviour of the system, not the processes.  The processes just 
    need to do their job.  The design of the workflow graph is based on the knowledge 
    of what each Process does so that the graph can be correctly constructed.
    The workflow graph can be constructed a priori or can be constructed and 
    modified by intelligent Processes as the system runs.


    The Hive is based on AI concepts and modeled on the social structure and 
    behaviour of a honey bee hive. So where a worker honey bee's purpose is
    (go find pollen, bring back to hive, drop off pollen, repeat), an ensembl-hive 
    worker's purpose is (find a job, create a Process for that job, run it,
    drop off output job(s), repeat).  While most workflow systems are based 
    on 'smart' central controllers and external control of 'dumb' processes, 
    the Hive is based on 'dumb' workflow graphs and job kiosk, and 'smart' workers 
    (autonomous agents) who are self configuring and figure out for themselves what 
    needs to be done, and then do it.  The workers are based around a set of 
    emergent behaviour rules which allow a predictible system behaviour to emerge 
    from what otherwise might appear at first glance to be a chaotic system. There 
    is an inherent asynchronous disconnect between one worker and the next.  
    Work (or jobs) are simply 'posted' on a blackboard or kiosk within the hive 
    database where other workers can find them.  
    The emergent behaviour rules of a worker are:
    1) If a job is posted, someone needs to do it.
    2) Don't grab something that someone else is working on
    3) Don't grab more than you can handle
    4) If you grab a job, it needs to be finished correctly
    5) Keep busy doing work
    6) If you fail, do the best you can to report back

    For further reading on the AI principles employed in this design see:
        http://en.wikipedia.org/wiki/Autonomous_Agent
        http://en.wikipedia.org/wiki/Emergence

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

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


package Bio::EnsEMBL::Hive::Process;

use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

use Bio::EnsEMBL::Hive::Utils ('stringify', 'go_figure_dbc', 'join_command_args');
use Bio::EnsEMBL::Hive::Utils::Stopwatch;


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    return $self;
}


sub life_cycle {
    my ($self) = @_;

    my $job = $self->input_job();
    my $partial_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my %job_partial_timing = ();

    $job->incomplete(1);    # reinforce, in case the life_cycle is not run by a Worker
    $job->autoflow(1);

    eval {
        if( $self->can('pre_cleanup') and $job->retry_count()>0 ) {
            $self->enter_status('PRE_CLEANUP');
            $self->pre_cleanup;
        }

        $self->enter_status('FETCH_INPUT');
        $partial_stopwatch->restart();
        $self->fetch_input;
        $job_partial_timing{'FETCH_INPUT'} = $partial_stopwatch->pause->get_elapsed;

        $self->enter_status('RUN');
        $partial_stopwatch->restart();
        $self->run;
        $job_partial_timing{'RUN'} = $partial_stopwatch->pause->get_elapsed;

        if($self->worker->execute_writes) {
            $self->enter_status('WRITE_OUTPUT');
            $partial_stopwatch->restart();
            $self->write_output;
            $job_partial_timing{'WRITE_OUTPUT'} = $partial_stopwatch->pause->get_elapsed;

            if( $self->can('post_healthcheck') ) {
                $self->enter_status('POST_HEALTHCHECK');
                $self->post_healthcheck;
            }
        } else {
            $self->say_with_header( ": *no* WRITE_OUTPUT requested, so there will be no AUTOFLOW" );
        }
    };

    if(my $life_cycle_msg = $@) {
        $job->died_somewhere( $job->incomplete );  # it will be OR'd inside
        Bio::EnsEMBL::Hive::Process::warning($self, $life_cycle_msg, $job->incomplete?'WORKER_ERROR':'INFO');     # In case the Runnable has redefined warning()
    }

    if( $self->can('post_cleanup') ) {   # may be run to clean up memory even after partially failed attempts
        eval {
            $job->incomplete(1);    # it could have been reset by a previous call to complete_early
            $self->enter_status('POST_CLEANUP');
            $self->post_cleanup;
        };
        if(my $post_cleanup_msg = $@) {
            $job->died_somewhere( $job->incomplete );  # it will be OR'd inside
            Bio::EnsEMBL::Hive::Process::warning($self, $post_cleanup_msg, $job->incomplete?'WORKER_ERROR':'INFO');   # In case the Runnable has redefined warning()
        }
    }

    unless( $job->died_somewhere ) {

        if( $self->execute_writes and $job->autoflow ) {    # AUTOFLOW doesn't have its own status so will have whatever previous state of the job
            $self->say_with_header( ': AUTOFLOW input->output' );
            $job->dataflow_output_id();
        }

        my @zombie_funnel_dataflow_rule_ids = keys %{$job->fan_cache};
        if( scalar(@zombie_funnel_dataflow_rule_ids) ) {
            $job->transient_error(0);
            die "The group of semaphored jobs is incomplete ! Some fan jobs (coming from dataflow_rule_id(s) ".join(',',@zombie_funnel_dataflow_rule_ids).") are missing a job on their funnel. Check the order of your dataflow_output_id() calls.";
        }

        $job->incomplete(0);

        return \%job_partial_timing;
    }
}


sub say_with_header {
    my ($self, $msg, $important) = @_;

    $important //= $self->debug();

    if($important) {
        if(my $worker = $self->worker) {
            $worker->worker_say( $msg );
        } else {
            print STDERR "StandaloneJob $msg\n";
        }
    }
}


sub enter_status {
    my ($self, $status) = @_;

    my $job = $self->input_job();

    $job->set_and_update_status( $status );

    if(my $worker = $self->worker) {
        $worker->set_and_update_status( 'JOB_LIFECYCLE' );  # to ensure when_checked_in TIMESTAMP is updated
    }

    $self->say_with_header( '-> '.$status );
}


sub warning {
    my ($self, $msg, $message_class) = @_;

    $message_class = 'WORKER_ERROR' if $message_class && looks_like_number($message_class);
    $message_class ||= 'INFO';
    chomp $msg;

    $self->say_with_header( "$message_class : $msg", 1 );

    my $job = $self->input_job;
    my $worker = $self->worker;

    if(my $job_adaptor = ($job && $job->adaptor)) {
        $job_adaptor->db->get_LogMessageAdaptor()->store_job_message($job->dbID, $msg, $message_class);
    } elsif(my $worker_adaptor = ($worker && $worker->adaptor)) {
        $worker_adaptor->db->get_LogMessageAdaptor()->store_worker_message($worker, $msg, $message_class);
    }
}


##########################################
#
# methods subclasses should override 
# in order to give this process function
#
##########################################


=head2 param_defaults

    Title   :  param_defaults
    Function:  sublcass can define defaults for all params used by the RunnableDB/Process

=cut

sub param_defaults {
    return {};
}


#
## Function: sublcass can implement functions related to cleaning up the database/filesystem after the previous unsuccessful run.
#

# sub pre_cleanup {
#    my $self = shift;
#
#    return 1;
# }


=head2 fetch_input

    Title   :  fetch_input
    Function:  sublcass can implement functions related to data fetching.
               Typical acivities would be to parse $self->input_id .
               Subclasses may also want to fetch data from databases
               or from files within this function.

=cut

sub fetch_input {
    my $self = shift;

    return 1;
}


=head2 run

    Title   :  run
    Function:  sublcass can implement functions related to process execution.
               Typical activities include running external programs or running
               algorithms by calling perl methods.  Process may also choose to
               parse results into memory if an external program was used.

=cut

sub run {
    my $self = shift;

    return 1;
}


=head2 write_output

    Title   :  write_output
    Function:  sublcass can implement functions related to storing results.
               Typical activities including writing results into database tables
               or into files on a shared filesystem.
               
=cut

sub write_output {
    my $self = shift;

    return 1;
}


#
## Function:  sublcass can implement functions related to cleaning up after running one job
#               (destroying non-trivial data structures in memory).
#

#sub post_cleanup {
#    my $self = shift;
#
#    return 1;
#}


######################################################
#
# methods that subclasses can use to get access
# to hive infrastructure
#
######################################################


=head2 worker

    Title   :   worker
    Usage   :   my $worker = $self->worker;
    Function:   returns the Worker object this Process is run by
    Returns :   Bio::EnsEMBL::Hive::Worker

=cut

sub worker {
    my $self = shift;

    $self->{'_worker'} = shift if(@_);
    return $self->{'_worker'};
}


sub execute_writes {
    my $self = shift;

    return $self->worker->execute_writes(@_);
}


=head2 db

    Title   :   db
    Usage   :   my $hiveDBA = $self->db;
    Function:   returns DBAdaptor to Hive database
    Returns :   Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=cut

sub db {
    my $self = shift;

    return $self->worker->adaptor && $self->worker->adaptor->db(@_);
}


=head2 dbc

    Title   :   dbc
    Usage   :   my $hiveDBConnection = $self->dbc;
    Function:   returns DBConnection to Hive database
    Returns :   Bio::EnsEMBL::Hive::DBSQL::DBConnection

=cut

sub dbc {
    my $self = shift;

    return $self->db && $self->db->dbc;
}


=head2 data_dbc

    Title   :   data_dbc
    Usage   :   my $data_dbc = $self->data_dbc;
    Function:   returns a Bio::EnsEMBL::Hive::DBSQL::DBConnection object (the "current" one by default, but can be set up otherwise)
    Returns :   Bio::EnsEMBL::Hive::DBSQL::DBConnection

=cut

sub data_dbc {
    my $self = shift @_;

    my $given_db_conn   = shift @_ || ($self->param_is_defined('db_conn') ? $self->param('db_conn') : $self);
    my $given_ref = ref( $given_db_conn );
    my $given_signature = ($given_ref eq 'ARRAY' or $given_ref eq 'HASH') ? stringify ( $given_db_conn ) : "$given_db_conn";

    if( !$self->{'_cached_db_signature'} or ($self->{'_cached_db_signature'} ne $given_signature) ) {
        $self->{'_cached_db_signature'} = $given_signature;
        $self->{'_cached_data_dbc'} = go_figure_dbc( $given_db_conn );
    }

    return $self->{'_cached_data_dbc'};
}


=head2 run_system_command

    Title   :  run_system_command
    Usage   :  my $return_code = $self->run_system_command('script.sh with many_arguments');   # Command as a single string
               my $return_code = $self->run_system_command(['script.sh', 'arg1', 'arg2']);     # Command as an array-ref
               my ($return_code, $stderr, $string_command) = $self->run_system_command(['script.sh', 'arg1', 'arg2']);     # Same in list-context. $string_command will be "script.sh arg1 arg2"
               my $return_code = $self->run_system_command('script1.sh with many_arguments | script2.sh', {'use_bash_pipefail' => 1});  # Command with pipes evaluated in a bash "pipefail" environment
    Function:  Runs a command given as a single-string or an array-ref. The second argument is
               a list of options. Currently only "use_bash_pipefail" is supported (to change the
               way the exit-code is computed when the command contains pipes (bash-only)).
    Returns :  Returns the return-code in scalar context, or a triplet (return-code, standard-error, command) in list context

=cut

sub run_system_command {
    my ($self, $cmd, $options) = @_;

    require Capture::Tiny;

    $options //= {};
    my ($join_needed, $flat_cmd) = join_command_args($cmd);
    # Let's use the array if possible, it saves us from running a shell
    my @cmd_to_run = $options->{'use_bash_pipefail'} ? ('bash' => ('-o' => 'pipefail', '-c' => $flat_cmd)) : ($join_needed ? $flat_cmd : (ref($cmd) ? @$cmd : $cmd));

    $self->say_with_header("Command given: " . stringify($cmd));
    $self->say_with_header("Command to run: " . stringify(\@cmd_to_run));

    $self->dbc and $self->dbc->disconnect_if_idle();    # release this connection for the duration of system() call

    my $return_value;

    # Capture:Tiny has weird behavior if 'require'd instead of 'use'd
    # see, for example,http://www.perlmonks.org/?node_id=870439 
    my $stderr = Capture::Tiny::tee_stderr(sub {
        $return_value = system(@cmd_to_run);
    });
    die sprintf("Could not run '%s', got %s\nSTDERR %s\n", $flat_cmd, $return_value, $stderr) if $return_value && $options->{die_on_failure};

    return ($return_value, $stderr, $flat_cmd) if wantarray;
    return $return_value;
}


=head2 input_job

    Title   :  input_job
    Function:  Returns the AnalysisJob to be run by this process
               Subclasses should treat this as a read_only object.          
    Returns :  Bio::EnsEMBL::Hive::AnalysisJob object

=cut

sub input_job {
    my $self = shift @_;

    if(@_) {
        if(my $job = $self->{'_input_job'} = shift) {
            throw("Not a Bio::EnsEMBL::Hive::AnalysisJob object") unless ($job->isa("Bio::EnsEMBL::Hive::AnalysisJob"));
        }
    }
    return $self->{'_input_job'};
}


# ##################### subroutines that link through to Job's methods #########################

sub input_id {
    my $self = shift;

    return $self->input_job->input_id(@_);
}

sub param {
    my $self = shift @_;

    return $self->input_job->param(@_);
}

sub param_required {
    my $self = shift @_;

    my $prev_transient_error = $self->input_job->transient_error(); # make a note of previously set transience status
    $self->input_job->transient_error(0);                           # make sure if we die in param_required it is not transient

    my $value = $self->input_job->param_required(@_);

    $self->input_job->transient_error($prev_transient_error);       # restore the previous transience status
    return $value;
}

sub param_is_defined {
    my $self = shift @_;

    return $self->input_job->param_is_defined(@_);
}

sub param_substitute {
    my $self = shift @_;

    return $self->input_job->param_substitute(@_);
}

sub dataflow_output_id {
    my $self = shift @_;

    $self->say_with_header(sprintf("Dataflow on branch #%d of %s", $_[1] || 1, stringify($_[0])));
    return $self->input_job->dataflow_output_id(@_);
}


sub throw {
    my $msg = pop @_;

    Bio::EnsEMBL::Hive::Utils::throw( $msg );   # this module doesn't import 'throw' to avoid namespace clash
}


sub complete_early {
    my ($self, $msg) = @_;

    $self->input_job->incomplete(0);
    die $msg;
}


=head2 debug

    Title   :  debug
    Function:  Gets/sets flag for debug level. Set through Worker/runWorker.pl
               Subclasses should treat as a read_only variable.
    Returns :  integer

=cut

sub debug {
    my $self = shift;

    return $self->worker->debug(@_);
}


=head2 worker_temp_directory

    Title   :  worker_temp_directory
    Function:  Returns a path to a directory on the local /tmp disk 
               which the subclass can use as temporary file space.
               This directory is made the first time the function is called.
               It persists for as long as the worker is alive.  This allows
               multiple jobs run by the worker to potentially share temp data.
               For example the worker (which is a single Analysis) might need
               to dump a datafile file which is needed by all jobs run through 
               this analysis.  The process can first check the worker_temp_directory
               for the file and dump it if it is missing.  This way the first job
               run by the worker will do the dump, but subsequent jobs can reuse the 
               file.
    Usage   :  $tmp_dir = $self->worker_temp_directory;
    Returns :  <string> path to a local (/tmp) directory 

=cut

sub worker_temp_directory {
    my $self = shift @_;

    unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
        $self->{'_tmp_dir'} = $self->worker_temp_directory_name();
        mkdir($self->{'_tmp_dir'}, 0777);
        throw("unable to create a writable directory ".$self->{'_tmp_dir'}) unless(-w $self->{'_tmp_dir'});
    }
    return $self->{'_tmp_dir'};
}

sub worker_temp_directory_name {
    my $self = shift @_;

    return $self->worker->temp_directory_name;
}


=head2 cleanup_worker_temp_directory

    Title   :  cleanup_worker_temp_directory
    Function:  Cleans up the directory on the local /tmp disk that is used for the
               worker. It can be used to remove files left there by previous jobs.
    Usage   :  $self->cleanup_worker_temp_directory;

=cut

sub cleanup_worker_temp_directory {
    my $self = shift @_;

    my $tmp_dir = $self->worker_temp_directory_name();
    if(-e $tmp_dir) {
        system('rm', '-r', $tmp_dir);
    }
}


1;

