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

sub refresh {
  my $self = shift;
  return unless($self->adaptor);
  $self->adaptor->refresh($self);
}

sub update {
  my $self = shift;
  return unless($self->adaptor);
  $self->adaptor->update($self);
}

sub update_status {
  my ($self, $status ) = @_;
  return unless($self->adaptor);
  $self->adaptor->update_status($self->analysis_id, $status);
  $self->status($status);
}

sub decrease_hive_capacity {
  my ($self) = @_;
  return unless ($self->adaptor);
  $self->adaptor->decrease_hive_capacity($self->analysis_id);
}

sub increase_hive_capacity {
  my ($self) = @_;
  return unless ($self->adaptor);
  $self->adaptor->increase_hive_capacity($self->analysis_id);
}

sub get_running_worker_count {
  my $self = shift;
  return unless ($self->adaptor);
  return $self->adaptor->get_running_worker_count($self);
}

sub analysis_id {
  my $self = shift;
  $self->{'_analysis_id'} = shift if(@_);
  return $self->{'_analysis_id'};
}

sub get_analysis {
  my $self = shift;
  unless($self->{'_analysis'}) {
    $self->{'_analysis'} = $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->analysis_id);
  }
  return $self->{'_analysis'};
}

sub status {
  my ($self, $value ) = @_;

  if(defined $value) {
    $self->{'_status'} = $value;
  }
  return $self->{'_status'};
}

sub batch_size {
  my $self = shift;
  $self->{'_batch_size'} = shift if(@_);
  $self->{'_batch_size'}=1 unless(defined($self->{'_batch_size'}));
  return $self->{'_batch_size'};
}

sub avg_msec_per_job {
  my $self = shift;
  $self->{'_avg_msec_per_job'} = shift if(@_);
  $self->{'_avg_msec_per_job'}=0 unless($self->{'_avg_msec_per_job'});
  return $self->{'_avg_msec_per_job'};
}

sub avg_input_msec_per_job {
  my $self = shift;
  $self->{'_avg_input_msec_per_job'} = shift if(@_);
  $self->{'_avg_input_msec_per_job'}=0 unless($self->{'_avg_input_msec_per_job'});
  return $self->{'_avg_input_msec_per_job'};
}

sub avg_run_msec_per_job {
  my $self = shift;
  $self->{'_avg_run_msec_per_job'} = shift if(@_);
  $self->{'_avg_run_msec_per_job'}=0 unless($self->{'_avg_run_msec_per_job'});
  return $self->{'_avg_run_msec_per_job'};
}

sub avg_output_msec_per_job {
  my $self = shift;
  $self->{'_avg_output_msec_per_job'} = shift if(@_);
  $self->{'_avg_output_msec_per_job'}=0 unless($self->{'_avg_output_msec_per_job'});
  return $self->{'_avg_output_msec_per_job'};
}

sub cpu_minutes_remaining {
  my $self = shift;
  return ($self->avg_msec_per_job * $self->unclaimed_job_count / 60000);
}

sub hive_capacity {
  my $self = shift;
  $self->{'_hive_capacity'} = shift if(@_);
  return $self->{'_hive_capacity'};
}

sub behaviour {
  my $self = shift;
  $self->{'_behaviour'} = shift if(@_);
  return $self->{'_behaviour'};
}

sub input_capacity {
  my $self = shift;
  $self->{'_input_capacity'} = shift if(@_);
  return $self->{'_input_capacity'};
}

sub output_capacity {
  my $self = shift;
  $self->{'_output_capacity'} = shift if(@_);
  return $self->{'_output_capacity'};
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

sub failed_job_count {
  my $self = shift;
  $self->{'_failed_job_count'} = shift if(@_);
  $self->{'_failed_job_count'} = 0 unless(defined($self->{'_failed_job_count'}));
  return $self->{'_failed_job_count'};
}

sub max_retry_count {
  my $self = shift;
  $self->{'_max_retry_count'} = shift if(@_);
  $self->{'_max_retry_count'} = 3 unless(defined($self->{'_max_retry_count'}));
  return $self->{'_max_retry_count'};
}

sub failed_job_tolerance {
  my $self = shift;
  $self->{'_failed_job_tolerance'} = shift if(@_);
  $self->{'_failed_job_tolerance'} = 0 unless(defined($self->{'_failed_job_tolerance'}));
  return $self->{'_failed_job_tolerance'};
}

sub running_job_count {
  my $self = shift;
  return $self->total_job_count
         - $self->done_job_count
         - $self->unclaimed_job_count
         - $self->failed_job_count;
}

sub remaining_job_count {
  my $self = shift;
  return $self->total_job_count
         - $self->done_job_count
         - $self->failed_job_count;
}

sub num_running_workers {
  my $self = shift;
  $self->{'_num_running_workers'} = shift if(@_);
  return $self->{'_num_running_workers'};
}

sub num_required_workers {
  my $self = shift;
  $self->{'_num_required_workers'} = shift if(@_);
  return $self->{'_num_required_workers'};
}

sub seconds_since_last_update {
  my( $self, $value ) = @_;
  $self->{'_last_update'} = time() - $value if(defined($value));
  return time() - $self->{'_last_update'};
}

sub sync_lock {
  my $self = shift;
  $self->{'_sync_lock'} = shift if(@_);
  return $self->{'_sync_lock'};
}

sub determine_status {
  my $self = shift;
  
  if($self->status ne 'BLOCKED') {
    if ($self->unclaimed_job_count == 0 and
        $self->total_job_count == $self->done_job_count + $self->failed_job_count) {
      my $failure_percentage = 0;
      if ($self->total_job_count) {
        $failure_percentage = $self->failed_job_count * 100 / $self->total_job_count;
      }
      if ($failure_percentage > $self->failed_job_tolerance) {
        $self->status('FAILED');
        print
            "\n",
            "##################################################\n",
            "##################################################\n",
            "##                                              ##\n";
        printf
            "##   ERROR: %-35s ##\n", $self->get_analysis->logic_name." failed!";
        printf
            "##          %4.1f%% jobs failed (tolerance: %3d%%) ##\n", $failure_percentage, $self->failed_job_tolerance;
        print
            "##                                              ##\n",
            "##################################################\n",
            "##################################################\n\n";
      } else {
        $self->status('DONE');
      }
    }
    if($self->total_job_count == $self->unclaimed_job_count) {
      $self->status('READY');
    }
    if($self->unclaimed_job_count>0 and
       $self->total_job_count > $self->unclaimed_job_count) {
      $self->status('WORKING');
    }
  }
  return $self;
}
  
sub print_stats {
  my $self = shift;
  my $mode = shift;

  return unless($self->get_analysis);

  $mode=1 unless($mode);

  my $name = sprintf("%s(%d)", $self->get_analysis->logic_name, $self->analysis_id);
  while(length($name) < 27) { $name.=' ';}

  if($mode == 1) {
    # printf("%s(%d) %s %d:ms %d:cpu (%d:q %d:r %d:d %d:f %d:t) [%d/%d workers] (%d secs synched)\n",
    #printf("%30s(%3d) %12s jobs(t:%d,q:%d,d:%d,f:%d) b:%d M:%d w:%d (%d secs old)\n",
    printf("$name %11s %d:cpum job(%d/%d run:%d fail:%d %dms) worker[%d/%d] (sync %d)\n",
        $self->status,
	$self->cpu_minutes_remaining,
        $self->remaining_job_count,
        $self->total_job_count,
        $self->running_job_count,
        $self->failed_job_count,
        $self->avg_msec_per_job,
        $self->num_required_workers, $self->hive_capacity,
        $self->seconds_since_last_update,
        );
  } elsif ($mode == 2) {
    printf("$name %11s [%d/%d workers] (%d secs synched)\n",
        $self->status,
        $self->num_required_workers, $self->hive_capacity,
        $self->seconds_since_last_update);

    printf("   msec_per_job   : %d\n", $self->avg_msec_per_job);
    printf("   cpu_min_total  : %d\n", $self->cpu_minutes_remaining);
    printf("   batch_size     : %d\n", $self->batch_size);
    printf("   total_jobs     : %d\n", $self->total_job_count);
    printf("   unclaimed jobs : %d\n", $self->unclaimed_job_count);
    printf("   running jobs   : %d\n", $self->running_job_count);
    printf("   done jobs      : %d\n", $self->done_job_count);
    printf("   failed jobs    : %d\n", $self->failed_job_count);
  }

}

1;
