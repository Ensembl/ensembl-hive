#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Process

=cut

=head1 SYNOPSIS

  Object categories to extend the functionality of existing classes

=cut

=head1 DESCRIPTION

=cut

=head1 CONTACT

  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=cut

=head1 APPENDIX

  The rest of the documentation details each of the object methods. 
  Internal methods are usually preceded with a _

=cut

my $g_hive_process_workdir;  # a global directory location for the process using this module

package Bio::EnsEMBL::Hive::Process;

use strict;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::AnalysisJob;

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  
  my ($analysis) = rearrange([qw( ANALYSIS )], @args);
  $self->analysis($analysis) if($analysis);
  
  return $self;
}

=head2 queen

    Title   :   queen
    Usage   :   my $hiveDBA = $self->db;
    Function:   getter/setter for 'Queen' this Process was created by
    Returns :   Bio::EnsEMBL::Hive::Queen

=cut

sub queen {
  my $self = shift;
  $self->{'_queen'} = shift if(@_);
  return $self->{'_queen'};
}

sub worker {
  my $self = shift;
  $self->{'_worker'} = shift if(@_);
  return $self->{'_worker'};
}

=head2 db

    Title   :   db
    Usage   :   my $hiveDBA = $self->db;
    Function:   returns DBAdaptor to Hive database
    Returns :   Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=cut

sub db {
  my $self = shift;
  return undef unless($self->queen);
  return $self->queen->db;
}

=head2 dbc

    Title   :   dbc
    Usage   :   my $hiveDBConnection = $self->dbc;
    Function:   returns DBConnection to Hive database
    Returns :   Bio::EnsEMBL::DBSQL::DBConnection

=cut

sub dbc {
  my $self = shift;
  return undef unless($self->queen);
  return $self->queen->dbc;
}

=head2 analysis

    Title   :  analysis
    Usage   :  $self->analysis;
    Function:  Gets or sets the stored Analysis object
               Set by Worker, available to get by the process.               
    Returns :  Bio::EnsEMBL::Analysis object
    Args    :  Bio::EnsEMBL::Analysis object

=cut

sub analysis {
  my ($self, $analysis) = @_;

  if($analysis) {
    throw("Not a Bio::EnsEMBL::Analysis object")
      unless ($analysis->isa("Bio::EnsEMBL::Analysis"));
    $self->{'_analysis'} = $analysis;
  }
  return $self->{'_analysis'};
}

=head2 input_job

    Title   :  input_job
    Function:  Gets or sets the AnalysisJob to be run by this process
               Set by Worker, available to get by the process.
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

=head2 autoflow_inputjob

    Title   :  autoflow_inputjob
    Function:  Gets/sets flag for whether the input_job should
               be automatically dataflowed on branch code 1 when the
               job completes.  If the subclass manually sends a job along
               branch 1 with dataflow_output_id, the autoflow will be turned off.
    Returns :  boolean (1/0/undef)

=cut

sub autoflow_inputjob {
  my $self = shift;
  $self->{'_autoflow_inputjob'} = shift if(@_);
  $self->{'_autoflow_inputjob'}=1 unless(defined($self->{'_autoflow_inputjob'}));  
  return $self->{'_autoflow_inputjob'};
}

=head2 dataflow_output_id

    Title        :  dataflow_output_id
    Arg[1](req)  :  <string> $output_id 
    Arg[2](opt)  :  <int> $branch_code (optional, defaults to 1)
    Usage        :  $self->dataflow_output_id($output_id, $branch_code);
    Function:  
      If Process needs to create jobs, this allows it to have 'extra' jobs 
      created and flowed through the dataflow rules of the analysis graph.
      This 'output_id' becomes the 'input_id' of the newly created job at
      the ends of the dataflow pipes.  The optional 'branch_code' determines
      which dataflow pipe(s) to flow the job through.      

=cut

sub dataflow_output_id {
  my ($self, $output_id, $branch_code, $blocked) = @_;

  return unless($output_id);
  return unless($self->analysis);

  $branch_code=1 unless(defined($branch_code));

  # Dataflow works by doing a transform from this process to the next.
  # The job starts out 'attached' to this process hence the analysis_id, branch_code, and dbID
  # are all relative to the starting point.  The dataflow process transforms the job to a 
  # different analysis_id, and moves the dbID to the previous_analysis_job_id
  
  my $job = new Bio::EnsEMBL::Hive::AnalysisJob;
  $job->input_id($output_id);
  $job->analysis_id($self->analysis->dbID);
  $job->branch_code($branch_code);
  $job->dbID($self->input_job->dbID);
  $job->status('READY');
  $job->status('BLOCKED') if(defined($blocked) and ($blocked eq 'BLOCKED'));
  
  #if process uses branch_code 1 explicitly, turn off automatic dataflow
  $self->autoflow_inputjob(0) if($branch_code==1);

  return $self->queen->flow_output_job($job);  
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


=head2 encode_hash

    Title   :  encode_hash
    Arg[1]  :  <reference to perl hash> $hash_ref 
    Function:  Simple convenience method which take a reference to a perl hash and
               returns a string which is perl code which can be converted back into
               the hash with an eval statement.  Treats all values in hash as strings
               so it will not properly encode complex data into perl.
    Usage   :  $hash_string = $self->encode_hash($has_ref);
               $hash_ref2 = eval($hash_string);
    Returns :  <string> perl code

=cut

sub encode_hash {
  my $self = shift;
  my $hash_ref = shift;

  return "" unless($hash_ref);

  my $hash_string = "{";
  my @keys = sort(keys %{$hash_ref});
  foreach my $key (@keys) {
    if(defined($hash_ref->{$key})) {
      $hash_string .= "'$key'=>'" . $hash_ref->{$key} . "',";
    }
  }
  $hash_string .= "}";

  return $hash_string;
}

=head2 worker_temp_directory

    Title   :  worker_temp_directory
    Function:  Returns a path to a directory on the local /tmp disk 
               which the subclass can use as temporary file space.
               This directory is made the first time the function is called.
               It presists for as long as the worker is alive.  This allows
               multiple jobs run by the worker to potentially share data.
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
  my $self = shift;
  return undef unless($self->worker);
  return $self->worker->worker_process_temp_directory;
}

#################################################
#
# methods to make porting from RunnableDB easier
#
#################################################

sub input_id {
  my $self = shift;
  return '' unless($self->input_job);
  return $self->input_job->input_id;
}

sub parameters {
  my $self = shift;
  return '' unless($self->analysis);
  return $self->analysis->parameters;
}


##########################################
#
# methods subclasses should override 
# in order to give this process function
#
##########################################

=head2 fetch_input

    Title   :  fetch_input
    Function:  sublcass should implement function related to data fetching.

=cut

sub fetch_input {
  my $self = shift;
  return 1;
}

=head2 run

    Title   :  run
    Function:  sublcass should implement function related to process execution.

=cut

sub run {
  my $self = shift;
  return 1;
}

=head2 write_output

    Title   :  write_output
    Function:  sublcass should implement function related to storing results.
    
=cut

sub write_output {
  my $self = shift;
  return 1;
}


1;

