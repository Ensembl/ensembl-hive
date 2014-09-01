=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Process

=head1 DESCRIPTION

    Abstract superclass.  Each Process makes up the individual building blocks 
    of the system.  Instances of these processes are created in a hive workflow 
    graph of Analysis entries that are linked together with dataflow and 
    AnalysisCtrl rules.
  
    Instances of these Processes are created by the system as work is done.
    The newly created Process will have preset $self->db, $self->dbc, 
    $self->input_id, $self->analysis and several other variables. 
    From this input and configuration data, each Process can then proceed to 
    do something.  The flow of execution within a Process is:
        pre_cleanup() if($retry_count>0);   # clean up databases/filesystem before subsequent attempts
        fetch_input();                      # fetch the data from databases/filesystems
        run();                              # perform the main computation 
        write_output();                     # record the results in databases/filesystems
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


package Bio::EnsEMBL::Hive::Process;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'go_figure_dbc');
use Bio::EnsEMBL::Hive::Utils::Stopwatch;


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    return $self;
}


sub life_cycle {
    my ($self, $worker) = @_;

    my $job = $self->input_job();
    my $partial_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my %job_partial_timing = ();

    $job->autoflow(1);

    if( $self->can('pre_cleanup') and $job->retry_count()>0 ) {
        $self->enter_status('PRE_CLEANUP');
        $self->pre_cleanup;
    }

    $self->enter_status('FETCH_INPUT');
    $partial_stopwatch->restart();
    $self->fetch_input;
    $job_partial_timing{'FETCH_INPUT'} = $partial_stopwatch->get_elapsed();

    $self->enter_status('RUN');
    $partial_stopwatch->restart();
    $self->run;
    $job_partial_timing{'RUN'} = $partial_stopwatch->get_elapsed();

    if($self->execute_writes) {
        $self->enter_status('WRITE_OUTPUT');
        $partial_stopwatch->restart();
        $self->write_output;
        $job_partial_timing{'WRITE_OUTPUT'} = $partial_stopwatch->get_elapsed();

        if( $job->autoflow ) {
            print STDERR "\njob ".$job->dbID." : AUTOFLOW input->output\n" if($self->debug);
            $job->dataflow_output_id();
        }
    } else {
        print STDERR "\n!!! *no* WRITE_OUTPUT requested, so there will be no AUTOFLOW\n" if($self->debug); 
    }

    if( $self->can('post_cleanup') ) {   # Todo: may need to run it after the eval, to clean up the memory even after partially failed attempts?
        $self->enter_status('POST_CLEANUP');
        $self->post_cleanup;
    }

    my @zombie_funnel_dataflow_rule_ids = keys %{$job->fan_cache};
    if( scalar(@zombie_funnel_dataflow_rule_ids) ) {
        $job->transient_error(0);
        die "There are cached semaphored fans for which a funnel job (dataflow_rule_id(s) ".join(',',@zombie_funnel_dataflow_rule_ids).") has never been dataflown";
    }

    return \%job_partial_timing;
}


sub enter_status {
    my ($self, $status) = @_;

    my $job = $self->input_job();

    $job->update_status( $status );

    my $status_msg  = 'Job '.$job->dbID.' : '.$status;

    if(my $worker = $self->worker) {
        $worker->enter_status( $status, $status_msg );
    } elsif($self->debug) {
        print STDERR "Standalone$status_msg\n";
    }
}


##########################################
#
# methods subclasses should override 
# in order to give this process function
#
##########################################

=head2 strict_hash_format

    Title   :  strict_hash_format
    Function:  if a subclass wants more flexibility in parsing job.input_id and analysis.parameters,
               it should redefine this method to return 0

=cut

sub strict_hash_format {
    return 1;
}


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
               Typical acivities would be to parse $self->input_id and read
               configuration information from $self->analysis.  Subclasses
               may also want to fetch data from databases or from files 
               within this function.

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


=head2 execute_writes

    Title   :   execute_writes
    Usage   :   $self->execute_writes( 1 );
    Function:   getter/setter for whether we want the 'write_output' method to be run
    Returns :   boolean

=cut

sub execute_writes {
    my $self = shift;

    $self->{'_execute_writes'} = shift if(@_);
    return $self->{'_execute_writes'};
}


=head2 db

    Title   :   db
    Usage   :   my $hiveDBA = $self->db;
    Function:   returns DBAdaptor to Hive database
    Returns :   Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=cut

sub db {
    my $self = shift;

    $self->{'_db'} = shift if(@_);
    return $self->{'_db'};
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


=head2 analysis

    Title   :  analysis
    Usage   :  $self->analysis;
    Function:  Returns the Analysis object associated with this
               instance of the Process.
    Returns :  Bio::EnsEMBL::Hive::Analysis object

=cut

sub analysis {
  my ($self, $analysis) = @_;

  if($analysis) {
    throw("Not a Bio::EnsEMBL::Hive::Analysis object")
      unless ($analysis->isa("Bio::EnsEMBL::Hive::Analysis"));
    $self->{'_analysis'} = $analysis;
  }
  return $self->{'_analysis'};
}

=head2 input_job

    Title   :  input_job
    Function:  Returns the AnalysisJob to be run by this process
               Subclasses should treat this as a read_only object.          
    Returns :  Bio::EnsEMBL::Hive::AnalysisJob object

=cut

sub input_job {
  my( $self, $job ) = @_;
  if($job) {
    throw("Not a Bio::EnsEMBL::Hive::AnalysisJob object")
        unless ($job->isa("Bio::EnsEMBL::Hive::AnalysisJob"));
    $self->{'_input_job'} = $job;
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

sub warning {
    my $self = shift @_;

    return $self->input_job->warning(@_);
}

sub dataflow_output_id {
    my $self = shift @_;

    return $self->input_job->dataflow_output_id(@_);
}


sub throw {
    my $msg = pop @_;

    Bio::EnsEMBL::Hive::Utils::throw( $msg );   # this module doesn't import 'throw' to avoid namespace clash
}


=head2 debug

    Title   :  debug
    Function:  Gets/sets flag for debug level. Set through Worker/runWorker.pl
               Subclasses should treat as a read_only variable.
    Returns :  integer

=cut

sub debug {
    my $self = shift;

    $self->{'_debug'} = shift if(@_);
    $self->{'_debug'}=0 unless(defined($self->{'_debug'}));  
    return $self->{'_debug'};
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

    my $username = $ENV{'USER'};
    my $worker_id = $self->worker ? $self->worker->dbID : "standalone.$$";
    return "/tmp/worker_${username}.${worker_id}/";
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
        my $cmd = "rm -r $tmp_dir";
        system($cmd);
    }
}


1;

