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
  my $self = shift;
  $self->{'_input_id'} = shift if(@_);
  return $self->{'_input_id'};
}

sub hive_id {
  my $self = shift;
  $self->{'_hive_id'} = shift if(@_);
  return $self->{'_hive_id'};
}

sub analysis_id {
  my $self = shift;
  $self->{'_analysis_id'} = shift if(@_);
  return $self->{'_analysis_id'};
}

sub job_claim {
  my $self = shift;
  $self->{'_job_claim'} = shift if(@_);
  return $self->{'_job_claim'};
}

sub status {
  my $self = shift;
  $self->{'_status'} = shift if(@_);
  return $self->{'_status'};
}

sub update_status {
  my ($self, $status ) = @_;
  return unless($self->adaptor);
  $self->status($status);
  $self->adaptor->update_status($self);
}

sub retry_count {
  my $self = shift;
  $self->{'_retry_count'} = shift if(@_);
  $self->{'_retry_count'} = 0 unless(defined($self->{'_retry_count'}));
  return $self->{'_retry_count'};
}

sub completed {
  my $self = shift;
  $self->{'_completed'} = shift if(@_);
  return $self->{'_completed'};
}

sub runtime_msec {
  my $self = shift;
  $self->{'_runtime_msec'} = shift if(@_);
  $self->{'_runtime_msec'} = 0 unless(defined($self->{'_runtime_msec'}));
  return $self->{'_runtime_msec'};
}

sub query_count {
  my $self = shift;
  $self->{'_query_count'} = shift if(@_);
  $self->{'_query_count'} = 0 unless(defined($self->{'_query_count'}));
  return $self->{'_query_count'};
}

sub branch_code {
  my $self = shift;
  $self->{'_branch_code'} = shift if(@_);
  $self->{'_branch_code'} = 1 unless(defined($self->{'_branch_code'}));
  return $self->{'_branch_code'};
}

sub stdout_file {
  my $self = shift;
  $self->{'_stdout_file'} = shift if(@_);
  return $self->{'_stdout_file'};
}

sub stderr_file {
  my $self = shift;
  $self->{'_stderr_file'} = shift if(@_);
  return $self->{'_stderr_file'};
}

sub print_job {
  my $self = shift;
  my $logic_name ='';
  $logic_name = $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->analysis_id)->logic_name if($self->adaptor);
  printf("job_id=%d %s(%d) retry=%d input_id='%s'\n", 
       $self->dbID,
       $logic_name,
       $self->analysis_id,
       $self->retry_count,
       $self->input_id);
}

1;
