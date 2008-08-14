#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Worker

=cut

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

=cut

=head1 CONTACT
 
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=cut

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Worker;

use strict;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Sys::Hostname;
use Time::HiRes qw(time);
use POSIX;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Hive::Process;

## Minimum amount of time in msec that a worker should run before reporting
## back to the hive. This is used when setting the batch_size automatically.
## 120000 msec = 2 minutes
my $MIN_BATCH_TIME = 120000;

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  return $self;
}

sub init {
  my $self = shift;
  $self->{'start_time'} = time();
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

sub life_span {
  #default life_span = 60minutes
  my( $self, $value ) = @_;
  $self->{'_life_span'} = 60*60 unless(defined($self->{'_life_span'}));
  $self->{'_life_span'} = $value if(defined($value));
  return $self->{'_life_span'};
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

sub hive_id {
  my( $self, $value ) = @_;
  $self->{'_hive_id'} = $value if($value);
  return $self->{'_hive_id'};
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

sub work_done {
  my( $self, $value ) = @_;
  $self->{'_work_done'} = 0 unless($self->{'_work_done'});
  $self->{'_work_done'} = $value if($value);
  return $self->{'_work_done'};
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

=head2 output_dir

  Arg [1] : (optional) string directory path
  Title   :   output_dir
  Usage   :   $value = $self->output_dir;
              $self->output_dir($new_value);
  Description: sets the directory where STDOUT and STRERR will be
	       redirected to. Each worker will create a subdirectory
	       where each analysis_job will get a .out and .err file
  Returntype : string

=cut

use Digest::MD5 qw(md5_hex);

sub output_dir {
  my ($self, $outdir) = @_;
  if ($outdir and (-d $outdir)) {
    my $hive_id = $self->hive_id;
    my (@hex) = md5_hex($hive_id) =~ m/\G(..)/g;
    # If you want more than one level of directories, change $hex[0]
    # below into an array slice.  e.g @hex[0..1] for two levels.
    $outdir = join('/', $outdir, $hex[0], 'hive_id_' . $hive_id);
    system("mkdir -p $outdir") && die "Could not create $outdir\n";
    $self->{'_output_dir'} = $outdir;
  }
  return $self->{'_output_dir'};
}


sub perform_global_cleanup {
  my $self = shift;
  $self->{'_perform_global_cleanup'} = shift if(@_);
  $self->{'_perform_global_cleanup'} = 1 unless(defined($self->{'_perform_global_cleanup'}));
  return $self->{'_perform_global_cleanup'};
}

sub print_worker {
  my $self = shift;
  print("WORKER: hive_id=",$self->hive_id,
     " analysis_id=(",$self->analysis->dbID,")",$self->analysis->logic_name,
     " host=",$self->host,
     " pid=",$self->process_id,
     "\n");
  print("  batch_size = ", $self->batch_size,"\n");
  print("  job_limit  = ", $self->job_limit,"\n") if(defined($self->job_limit));
  print("  life_span  = ", $self->life_span,"\n") if(defined($self->life_span));
  if($self->output_dir) {
    print("  output_dir = ", $self->output_dir, "\n") if($self->output_dir);
  } else {
    print("  output_dir = STDOUT/STDERR\n")
  }
}


sub worker_process_temp_directory {
  my $self = shift;
  
  unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
    #create temp directory to hold fasta databases
    $self->{'_tmp_dir'} = "/tmp/worker.$$/";
    mkdir($self->{'_tmp_dir'}, 0777);
    throw("unable to create ".$self->{'_tmp_dir'}) unless(-e $self->{'_tmp_dir'});
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

sub run
{
  my $self = shift;
  my $specific_job = $self->_specific_job;

  if($self->output_dir()) {
    open OLDOUT, ">&STDOUT";
    open OLDERR, ">&STDERR";
    open WORKER_STDOUT, ">".$self->output_dir()."/worker.out";
    open WORKER_STDERR, ">".$self->output_dir()."/worker.err";
    close STDOUT;
    close STDERR;
    open STDOUT, ">&WORKER_STDOUT";
    open STDERR, ">&WORKER_STDERR";
  }
  $self->print_worker();

  $self->db->dbc->disconnect_when_inactive(0);

  my $alive = 1;
  while ($alive) {
    my $batch_start = time() * 1000;    
    my $batch_end = $batch_start;
    my $job_counter = 0;
    my $jobs = [];
    $self->{fetch_time} = 0;
    $self->{run_time} = 0;
    $self->{write_time} = 0;

    do {
      if($specific_job) {
        $self->queen->worker_reclaim_job($self,$specific_job);
        push @$jobs, $specific_job;
        $alive=undef;
      } else {
        $jobs = $self->queen->worker_grab_jobs($self);
      }

      $self->queen->worker_check_in($self); #will sync analysis_stats if needed

      $self->cause_of_death('NO_WORK') unless(scalar @{$jobs});

      if($self->debug) {
        $self->analysis->stats->print_stats;
        print(STDOUT "claimed ",scalar(@{$jobs}), " jobs to process\n");
      }

      foreach my $job (@{$jobs}) {
        $job->print_job if($self->debug); 

        $self->redirect_job_output($job);
        $self->run_module_with_job($job);
        $self->close_and_update_job_output($job);

        $self->queen->worker_register_job_done($self, $job);

        $self->{'_work_done'}++;
      }
      $batch_end = time() * 1000;
      $job_counter += scalar(@$jobs);
    } while (!$specific_job and scalar(@$jobs) and $batch_end-$batch_start < $MIN_BATCH_TIME); ## Run for $MIN_BATCH_TIME at least

    #printf("batch start:%f end:%f\n", $batch_start, $batch_end);
    $self->db->get_AnalysisStatsAdaptor->interval_update_work_done($self->analysis->dbID,
        $job_counter, $batch_end-$batch_start, $self);

    $self->cause_of_death('JOB_LIMIT') if($specific_job);

    if($self->job_limit and ($self->{'_work_done'} >= $self->job_limit)) { 
      $self->cause_of_death('JOB_LIMIT'); 
    }
    if(($self->life_span()>0) and ((time() - $self->{'start_time'}) > $self->life_span())) {
      printf("life_span exhausted (alive for %d secs)\n", (time() - $self->{'start_time'}));
      $self->cause_of_death('LIFESPAN'); 
    }

    if (!$self->cause_of_death and $self->analysis->stats->num_running_workers > $self->analysis->stats->hive_capacity) {
      my $sql = "UPDATE analysis_stats SET num_running_workers = num_running_workers - 1 ".
                "WHERE num_running_workers > hive_capacity AND analysis_id = " . $self->analysis->stats->analysis_id;
      my $row_count = $self->queen->dbc->do($sql);
      if ($row_count == 1) {
        $self->cause_of_death('HIVE_OVERLOAD');
      }
    }
    if($self->cause_of_death) { $alive=undef; }
  }
  $self->queen->dbc->do("UPDATE hive SET status = 'DEAD' WHERE hive_id = ".$self->hive_id);
  
  if($self->perform_global_cleanup) {
    #have runnable cleanup any global/process files/data it may have created
    $self->cleanup_worker_process_temp_directory;
  }

  $self->queen->register_worker_death($self);

  $self->analysis->stats->print_stats if($self->debug);

  printf("dbc %d disconnect cycles\n", $self->db->dbc->disconnect_count);
  print("total jobs completes : ", $self->work_done, "\n");
  
  if($self->output_dir()) {
    close STDOUT;
    close STDERR;
    close WORKER_STDOUT;
    close WORKER_STDERR;
    open STDOUT, ">&", \*OLDOUT;
    open STDERR, ">&", \*OLDERR;
  }
}


sub run_module_with_job
{
  my $self = shift;
  my $job  = shift;

  my ($start_time, $end_time);

  my $runObj = $self->analysis->process;
  return 0 unless($runObj);
  return 0 unless($job and ($job->hive_id eq $self->hive_id));
  
  my $init_time = time() * 1000;
  $self->queen->dbc->query_count(0);

  #pass the input_id from the job into the Process object
  if($runObj->isa("Bio::EnsEMBL::Hive::Process")) { 
    $runObj->input_job($job);
    $runObj->queen($self->queen);
    $runObj->worker($self);
    $runObj->debug($self->debug);
  } else {
    $runObj->input_id($job->input_id);
    $runObj->db($self->db);
  }

  my $analysis_stats = $self->analysis->stats;

  $self->enter_status("GET_INPUT");
  $job->update_status('GET_INPUT');
  print("\nGET_INPUT\n") if($self->debug); 

  $start_time = time() * 1000;
  $runObj->fetch_input;
  $end_time = time() * 1000;
  $self->{fetch_time} += $end_time - $start_time;

  $self->enter_status("RUN");
  $job->update_status('RUN');
  print("\nRUN\n") if($self->debug); 

  $start_time = time() * 1000;
  $runObj->run;
  $end_time = time() * 1000;
  $self->{run_time} += $end_time - $start_time;

  if($self->execute_writes) {
    $self->enter_status("WRITE_OUTPUT");
    $job->update_status('WRITE_OUTPUT');
    print("\nWRITE_OUTPUT\n") if($self->debug); 

    $start_time = time() * 1000;
    $runObj->write_output;
    $end_time = time() * 1000;
    $self->{write_time} += $end_time - $start_time;
  } else {
    print("\n\n!!!! NOT write_output\n\n\n") if($self->debug); 
  }
  $self->enter_status("READY");

  $job->query_count($self->queen->dbc->query_count);
  $job->runtime_msec(time()*1000 - $init_time);

  if ($runObj->isa("Bio::EnsEMBL::Hive::Process") and $runObj->autoflow_inputjob
      and $self->execute_writes) {
    printf("AUTOFLOW input->output\n") if($self->debug);
    $self->queen->flow_output_job($job);
  }

  return 1;
}

sub enter_status {
  my ($self, $status) = @_;
  return $self->queen->enter_status($self, $status);
}

sub redirect_job_output
{
  my $self = shift;
  my $job  = shift;

  my $outdir = $self->output_dir();
  return unless($outdir);
  return unless($job);
  return unless($job->adaptor);

  $job->stdout_file($outdir . "/job_".$job->dbID.".out");
  $job->stderr_file($outdir . "/job_".$job->dbID.".err");

  close STDOUT;
  open STDOUT, ">".$job->stdout_file;

  close STDERR;
  open STDERR, ">".$job->stderr_file;

  $job->adaptor->store_out_files($job) if($job->adaptor);
}


sub close_and_update_job_output
{
  my $self = shift;
  my $job  = shift;

  return unless($job);
  return unless($self->output_dir);
  return unless($job->adaptor);


  # the following flushes $job->stderr_file and $job->stdout_file
  open STDOUT, ">&WORKER_STDOUT";
  open STDERR, ">&WORKER_STDERR";

  if(-z $job->stdout_file) {
    #print("unlink zero size ", $job->stdout_file, "\n");
    unlink $job->stdout_file;
    $job->stdout_file('');
  }
  if(-z $job->stderr_file) {
    #print("unlink zero size ", $job->stderr_file, "\n");
    unlink $job->stderr_file;
    $job->stderr_file('');
  }

  $job->adaptor->store_out_files($job) if($job->adaptor);

}


sub check_system_load {
  my $self = shift;

  my $host = hostname;
  my $numCpus = `grep -c '^process' /proc/cpuinfo`;
  print("host: $host  cpus:$numCpus\n");

  return 1;  #everything ok
}

sub _specific_job {
  my $self = shift;
  $self->{'_specific_job'} = shift if(@_);
  return $self->{'_specific_job'};
}

1;
