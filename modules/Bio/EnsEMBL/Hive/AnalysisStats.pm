#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME
  Bio::EnsEMBL::Hive::AnalysisStats

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONTACT
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX
  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _
=cut

package Bio::EnsEMBL::Hive::AnalysisStats;

use strict;

use Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;

use vars qw(@ISA);

@ISA = qw(Bio::EnsEMBL::Root);

=head3
CREATE TABLE analysis_stats (
  analysis_id           int(10) NOT NULL,
  status                enum('BLOCKED', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE')
                          DEFAULT 'READY' NOT NULL,
  batch_size            int(10) NOT NULL,
  hive_capacity         int(10) NOT NULL,
  total_job_count       int(10) NOT NULL,
  unclaimed_job_count   int(10) NOT NULL,
  done_job_count        int(10) NOT NULL,
  num_required_workers  int(10) NOT NULL,
  last_update           datetime NOT NULL,

  UNIQUE KEY   (analysis_id)
);
=cut


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

sub status {
  my ($self, $value ) = @_;

  if(defined $value) {
    $self->{'_status'} = $value;
    $self->adaptor->update_status($self->dbID, $value) if($self->adaptor);
  }
  return $self->{'_status'};
}

sub batch_size {
  my $self = shift;
  $self->{'_batch_size'} = shift if(@_);
  return $self->{'_batch_size'};
}

sub hive_capacity {
  my $self = shift;
  $self->{'_hive_capacity'} = shift if(@_);
  return $self->{'_hive_capacity'};
}

sub total_job_count {
  my $self = shift;
  $self->{'_total_job_count'} = shift if(@_);
  return $self->{'_total_job_count'};
}

sub unclaimed_job_count {
  my $self = shift;
  $self->{'_unclaimed_job_count'} = shift if(@_);
  return $self->{'_unclaimed_job_count'};
}

sub done_job_count {
  my $self = shift;
  $self->{'_done_job_count'} = shift if(@_);
  return $self->{'_done_job_count'};
}

sub num_required_workers {
  my $self = shift;
  $self->{'_num_required_workers'} = shift if(@_);
  return $self->{'_num_required_workers'};
}

sub seconds_since_last_update {
  my( $self, $value ) = @_;
  $self->{'_last_update'} = time() + $value if(defined($value));
  return time() - $self->{'_last_update'};
}

sub print_stats {
  my $self = shift;
  print("ANALYSIS_STATS: analysis_id=",$self->dbID,"\n"
       ," status=",$self->status,"\n"
       ," batch_size=",$self->batch_size,"\n"
       ," hive_capacity=" . $self->hive_capacity(),"\n"
       ,",total_job_count=" . $self->total_job_count(),"\n"
       ,",unclaimed_job_count=" . $self->unclaimed_job_count(),"\n"
       ,",done_job_count=" . $self->done_job_count(),"\n"
       ,",num_required_workers=" . $self->num_required_workers(),"\n"
       ,",last_update==", $self->{'_last_update'},"\n");
}

1;
