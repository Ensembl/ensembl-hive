#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::AnalysisJob

=head1 DESCRIPTION

  An AnalysisJob is the link between the input_id control data, the analysis and
  the rule system.  It also tracks the state of the job as it is processed

=head1 CONTACT

  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Hive::AnalysisJob;

use strict;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  return $self;
}

sub adaptor {
  my $self = shift;
  $self->{'_adaptor'} = shift if(@_);
  return $self->{'_adaptor'};
}

sub dbID {
  my $self = shift;
  $self->{'_dbID'} = shift if(@_);
  return $self->{'_dbID'};
}

sub input_id {
  my( $self, $value ) = @_;
  $self->{'_input_id'} = $value if($value);
  return $self->{'_input_id'};
}

sub hive_id {
  my $self = shift;
  $self->{'_hive_id'} = shift if(@_);
  return $self->{'_hive_id'};
}

sub analysis_id {
  my( $self, $value ) = @_;
  $self->{'_analysis_id'} = $value if($value);
  return $self->{'_analysis_id'};
}

sub job_claim {
  my( $self, $value ) = @_;
  $self->{'_job_claim'} = $value if($value);
  return $self->{'_job_claim'};
}

sub status {
  my( $self, $value ) = @_;

  if($value) {
    $self->{'_status'} = $value;
    $self->adaptor->update_status($self) if($self->adaptor);
  }
  return $self->{'_status'};
}

sub retry_count {
  my( $self, $value ) = @_;
  $self->{'_retry_count'} = $value if($value);
  return $self->{'_retry_count'};
}

sub completed {
  my( $self, $value ) = @_;
  $self->{'_completed'} = $value if($value);
  return $self->{'_completed'};
}

sub branch_code {
  my( $self, $value ) = @_;
  $self->{'_branch_code'} = $value if(defined($value));
  $self->{'_branch_code'} = 1 unless(defined($self->{'_branch_code'}));
  return $self->{'_branch_code'};
}

sub stdout_file {
  my( $self, $value ) = @_;
  $self->{'_stdout_file'} = $value if(defined($value));
  return $self->{'_stdout_file'};
}

sub stderr_file {
  my( $self, $value ) = @_;
  $self->{'_stderr_file'} = $value if(defined($value));
  return $self->{'_stderr_file'};
}

sub print_job {
  my $self = shift;
  print("WORKER: hive_id=",$self->hive_id,
     " host=",$self->host,
     " ppid=",$self->process_id,
     "\n");  
}

1;
