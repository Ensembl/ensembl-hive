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
    Returns :  Bio::EnsEMBL::Analysis object

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

=head2 dataflow_output_id

    Title        :  dataflow_output_id
    Arg[1](req)  :  <string> $output_id 
    Arg[2](opt)  :  <int> $branch_code (optional, defaults to 1)
    Usage        :  $self->dataflow_output_id($output_id, $branch_code);
    Function:  
      If Process needs to create jobs, this allows it to have 'extra' jobs 
      created and flowed through the dataflow rules of the analysis graph.
      The 'output_id' becomes the 'input_id' of the newly created job and
      the ends of the dataflow pipes.  The optional 'branch_code' determines
      which pipe(s) to flow the job through.      

=cut

sub dataflow_output_id {
  my ($self, $output_id, $branch_code) = @_;

  return unless($output_id);
  return unless($self->analysis);

  my $job = new Bio::EnsEMBL::Hive::AnalysisJob;
  $job->input_id($output_id);
  $job->analysis_id($self->analysis->dbID);
  $job->branch_code($branch_code) if(defined($branch_code));

  $self->queen->flow_output_job($job);  
}

sub debug {
  my $self = shift;
  $self->{'_debug'} = shift if(@_);
  $self->{'_debug'}=0 unless(defined($self->{'_debug'}));  
  return $self->{'_debug'};
}


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


sub worker_temp_directory {
  unless(defined($g_hive_process_workdir) and (-e $g_hive_process_workdir)) {
    #create temp directory to hold fasta databases
    $g_hive_process_workdir = "/tmp/worker.$$/";
    mkdir($g_hive_process_workdir, 0777);
  }
  return $g_hive_process_workdir;
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


sub fetch_input {
  my $self = shift;
  return 1;
}

sub run {
  my $self = shift;
  return 1;
}

sub write_output {
  my $self = shift;
  return 1;
}

sub global_cleanup {
  if($g_hive_process_workdir) {
    unlink(<$g_hive_process_workdir/*>);
    rmdir($g_hive_process_workdir);
  }
  return 1;
}

1;

