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
  put it when it's done (put in next person's INBOX) so the next Worker
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

  The Queen's primary job is to create Workers to get the work down.
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
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX
  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Hive::Worker;

use strict;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;
use Bio::EnsEMBL::Hive::Extensions;

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  return $self;
}

sub init {
  my $self = shift;
  $self->{'start_time'} = time();
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

sub output_dir {
  my( $self, $outdir ) = @_;
  if($outdir and (-d $outdir)) {
    $outdir .= "/worker_" . $self->hive_id ."/";
    mkdir($outdir);
    $self->{'_output_dir'} = $outdir 
  }
  return $self->{'_output_dir'};
}

sub job_limit {
  my $self=shift;
  if(@_) {
    $self->{'_job_limit'}=shift;
    if($self->{'_job_limit'} < $self->batch_size) {
      $self->batch_size($self->{'_job_limit'});
    }
  }
  return $self->{'_job_limit'};
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
  print("  output_dir = ", $self->output_dir, "\n") if($self->output_dir);
}

###############################
#
# WORK section
#
###############################
=head2 batch_size
  Arg [1] : (optional) string $value
  Title   :   batch_size
  Usage   :   $value = $self->batch_size;
              $self->batch_size($new_value);
  Description: Defines the number of jobs that should run in batch
               before querying the database for the next job batch.  Used by the
               Hive system to manage the number of workers needed to complete a
               particular job type.
  DefaultValue : batch_size of runnableDB in analysis
  Returntype : integer scalar
=cut

sub batch_size {
  my $self = shift;
  if(@_) { $self->{'_batch_size'} = shift; }
  do {
    my $runObj = $self->analysis->runnableDB;
    $self->{'_batch_size'} = $runObj->batch_size if($runObj);
  } unless($self->{'_batch_size'});
  return $self->{'_batch_size'};
}


sub run
{
  my $self = shift;

  if($self->output_dir()) {
    open OLDOUT, ">&STDOUT";
    open OLDERR, ">&STDERR";
    open WORKER_STDOUT, ">".$self->output_dir()."worker.out";
    open WORKER_STDERR, ">".$self->output_dir()."worker.err";
    close STDOUT;
    close STDERR;
    open STDOUT, ">&WORKER_STDOUT";
    open STDERR, ">&WORKER_STDERR";
  }
  $self->print_worker();

  $self->db->dbc->disconnect_when_inactive(1);

  my $jobDBA = $self->db->get_AnalysisJobAdaptor;
  my $alive=1;  
  while($alive) {
    my $claim = $jobDBA->claim_jobs_for_worker($self);
    my $jobs = $jobDBA->fetch_by_claim_analysis($claim, $self->analysis->dbID);

    $self->queen->worker_check_in($self);

    $self->cause_of_death('NO_WORK') unless(scalar @{$jobs});

    print(STDOUT "claimed ",scalar(@{$jobs}), " jobs to process\n");
    foreach my $job (@{$jobs}) {
      $self->redirect_job_output($job);
      $self->run_module_with_job($job);
      $self->create_next_jobs($job);
      $job->status('DONE');
      $self->close_and_update_job_output($job);
      $self->{'_work_done'}++;
    }
    if($self->job_limit and ($self->{'_work_done'} >= $self->job_limit)) { 
      $self->cause_of_death('JOB_LIMIT'); 
    }
    if(($self->life_span()>0) and ((time() - $self->{'start_time'}) > $self->life_span())) {
      printf("life_span exhausted (alive for %d secs)\n", (time() - $self->{'start_time'}));
      $self->cause_of_death('LIFESPAN'); 
    }
    if($self->cause_of_death) { $alive=undef; }
  }

  $self->queen->register_worker_death($self);

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

  my $runObj = $self->analysis->runnableDB;
  return 0 unless($runObj);
  return 0 unless($job and ($job->hive_id eq $self->hive_id));
  
  #pass the input_id from the job into the runnableDB object
  $runObj->input_id($job->input_id);
  
  #$job->status('GET_INPUT');
  $runObj->fetch_input;

  $job->status('RUN');
  $runObj->run;

  $job->status('WRITE_OUTPUT');
  my $branch_code = $runObj->write_output;

  #runnableDB is allowed to alter it is input_id on output
  #This modified input_id is passed as input to the next jobs in the graph
  $job->input_id($runObj->input_id);
  $job->branch_code($branch_code);

  return 1;
}


sub create_next_jobs
{
  my $self = shift;
  my $job  = shift;

  return unless($self->db);

  my $rules = $self->db->get_DataflowRuleAdaptor->fetch_from_analysis_job($job);

  foreach my $rule (@{$rules}) {
    Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
        -input_id       => $job->input_id,
        -analysis       => $rule->to_analysis,
        -input_job_id   => $job->dbID,
    );
  }
}


sub redirect_job_output
{
  my $self = shift;
  my $job  = shift;

  my $outdir = $self->output_dir();
  return unless($outdir);
  return unless($job);

  $job->stdout_file($outdir . "job_".$job->dbID.".out");
  $job->stderr_file($outdir . "job_".$job->dbID.".err");

  close STDOUT;
  open STDOUT, ">".$job->stdout_file;

  close STDERR;
  open STDERR, ">".$job->stderr_file;
}


sub close_and_update_job_output
{
  my $self = shift;
  my $job  = shift;

  return unless($job);
  return unless($self->output_dir);

  close STDOUT;
  close STDERR;
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


1;
