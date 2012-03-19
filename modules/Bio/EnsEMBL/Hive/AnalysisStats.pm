#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::AnalysisStats

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisStats;

use strict;
use Scalar::Util ('weaken');

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;

    ## Minimum amount of time in msec that a worker should run before reporting
    ## back to the hive. This is used when setting the batch_size automatically.
sub min_batch_time {
    return 2*60*1000;
}


sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  return $self;
}


sub adaptor {
    my $self = shift @_;

    if(@_) {
        $self->{'_adaptor'} = shift @_;
        weaken $self->{'_adaptor'};
    }

    return $self->{'_adaptor'};
}


sub refresh {
    my $self = shift;

    return $self->adaptor && $self->adaptor->refresh($self);
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
    $self->{'_batch_size'} = 1 unless(defined($self->{'_batch_size'})); # only initialize when undefined, so if defined as 0 will stay 0

    return $self->{'_batch_size'};
}

sub get_or_estimate_batch_size {
    my $self = shift;

    if( (my $batch_size = $self->batch_size())>0 ) {        # set to positive or not set (and auto-initialized within $self->batch_size)

        return $batch_size;
                                                        # otherwise it is a request for dynamic estimation:
    } elsif( my $avg_msec_per_job = $self->avg_msec_per_job() ) {           # further estimations from collected stats

        $avg_msec_per_job = 100 if($avg_msec_per_job<100);

        return POSIX::ceil( $self->min_batch_time() / $avg_msec_per_job );

    } else {        # first estimation when no stats are available (take -$batch_size as first guess, if not zero)
        return -$batch_size || 1;
    }
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

sub rc_id {
    my $self = shift;

    $self->{'_rc_id'} = shift if(@_);
    return $self->{'_rc_id'};
}

sub can_be_empty {
    my $self = shift;

    $self->{'_can_be_empty'} = shift if(@_);
    return $self->{'_can_be_empty'};
}

sub priority {
    my $self = shift;

    $self->{'_priority'} = shift if(@_);
    return $self->{'_priority'};
}
  
sub print_stats {
  my $self = shift;
  my $mode = shift;

  return unless($self->get_analysis);

  $mode=1 unless($mode);

  if($mode == 1) {
    printf("%-27s(%2d) %11s %d:cpum job(%d/%d run:%d fail:%d %dms) worker[%d/%d] (sync'd %d sec ago)\n",
        $self->get_analysis->logic_name,
        $self->analysis_id,
        $self->status,
        $self->cpu_minutes_remaining,
        $self->remaining_job_count,
        $self->total_job_count,
        $self->running_job_count,
        $self->failed_job_count,
        $self->avg_msec_per_job,
        $self->num_required_workers,
        $self->hive_capacity,
        $self->seconds_since_last_update,
    );
  } elsif ($mode == 2) {
    printf("%-27s(%2d) %11s [%d/%d workers] (sync'd %d sec ago)\n",
        $self->get_analysis->logic_name,
        $self->analysis_id,
        $self->status,
        $self->num_required_workers,
        $self->hive_capacity,
        $self->seconds_since_last_update
    );

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


sub check_blocking_control_rules {
    my $self = shift;
  
    my $ctrl_rules = $self->adaptor->db->get_AnalysisCtrlRuleAdaptor->fetch_all_by_ctrled_analysis_id($self->analysis_id);

    my $all_ctrl_rules_done = 1;

    if(scalar @$ctrl_rules) {    # there are blocking ctrl_rules to check

        foreach my $ctrl_rule (@$ctrl_rules) {
                #use this method because the condition_analysis objects can be
                #network distributed to a different database so use it's adaptor to get
                #the AnalysisStats object
            my $condition_analysis              = $ctrl_rule->condition_analysis;
            my $condition_analysis_stats        = $condition_analysis && $condition_analysis->stats;
            my $condition_analysis_stats_status = $condition_analysis_stats && $condition_analysis_stats->status;
            my $condition_analysis_stats_cbe    = $condition_analysis_stats && $condition_analysis_stats->can_be_empty;

            my $unblocked_condition = ($condition_analysis_stats_status eq 'DONE')
                        || ($condition_analysis_stats_cbe && ($condition_analysis_stats_status eq 'READY'));

            unless( $unblocked_condition ) {
                $all_ctrl_rules_done = 0;
            }
        }

        if($all_ctrl_rules_done) {
            if($self->status eq 'BLOCKED') {    # unblock, since all conditions are met
                $self->update_status('LOADING'); # trigger sync
            }
        } else {    # (re)block
            $self->update_status('BLOCKED');
        }
    }

    return $all_ctrl_rules_done;
}


sub determine_status {
    my $self = shift;

    if($self->status ne 'BLOCKED') {
        if($self->unclaimed_job_count == $self->total_job_count) {     # nothing has been claimed yet (or an empty analysis)

            $self->status('READY');

        } elsif( $self->total_job_count == $self->done_job_count + $self->failed_job_count ) {   # all jobs of the analysis have been tried
            my $absolute_tolerance = $self->failed_job_tolerance * $self->total_job_count / 100.0;
            if ($self->failed_job_count > $absolute_tolerance) {
                $self->status('FAILED');
                print "\n##################################################\n";
                printf("##   ERROR: %-35s ##\n", $self->get_analysis->logic_name." failed!");
                printf("##     %d jobs failed (tolerance: %d (%3d%%)) ##\n", $self->failed_job_count, $absolute_tolerance, $self->failed_job_tolerance);
                print "##################################################\n\n";
            } else {
                $self->status('DONE');
            }
        } elsif ($self->unclaimed_job_count == 0 ) {                        # everything has been claimed

            $self->status('ALL_CLAIMED');

        } elsif( 0 < $self->unclaimed_job_count and $self->unclaimed_job_count < $self->total_job_count ) {

            $self->status('WORKING');
        }
    }
}


1;
