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

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use Bio::EnsEMBL::Hive::Analysis;


    ## Minimum amount of time in msec that a worker should run before reporting
    ## back to the hive. This is used when setting the batch_size automatically.
sub min_batch_time {
    return 2*60*1000;
}


sub new {
    my $class = shift;
    my $self = bless {}, $class;

    my ($analysis_id, $batch_size, $hive_capacity, $status) = 
      rearrange([qw(analysis_id batch_size hive_capacity status) ], @_);

    $self->analysis_id($analysis_id)                    if(defined($analysis_id));
    $self->batch_size($batch_size)                      if(defined($batch_size));
    $self->hive_capacity($hive_capacity)                if(defined($hive_capacity));
    $self->status($status)                              if(defined($status));

    return $self;
}


## pre-settable storable object's getters/setters:


sub adaptor {
    my $self = shift;

    if(@_) {
        $self->{'_adaptor'} = shift;
        weaken $self->{'_adaptor'};
    }
    return $self->{'_adaptor'};
}

sub analysis_id {
    my $self = shift;
    $self->{'_analysis_id'} = shift if(@_);
    return $self->{'_analysis_id'};
}

sub batch_size {
    my $self = shift;
    $self->{'_batch_size'} = shift if(@_);
    $self->{'_batch_size'} = 1 unless(defined($self->{'_batch_size'})); # only initialize when undefined, so if defined as 0 will stay 0
    return $self->{'_batch_size'};
}

sub hive_capacity {
    my $self = shift;
    $self->{'_hive_capacity'} = shift if(@_);
    return $self->{'_hive_capacity'};
}

sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    return $self->{'_status'};
}


## counters of jobs in different states:


sub total_job_count {
    my $self = shift;
    $self->{'_total_job_count'} = shift if(@_);
    return $self->{'_total_job_count'};
}

sub semaphored_job_count {
    my $self = shift;
    $self->{'_semaphored_job_count'} = shift if(@_);
    return $self->{'_semaphored_job_count'};
}

sub ready_job_count {
    my $self = shift;
    $self->{'_ready_job_count'} = shift if(@_);
    return $self->{'_ready_job_count'};
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

sub num_running_workers {
    my $self = shift;
    $self->{'_num_running_workers'} = shift if(@_);
    return $self->{'_num_running_workers'};
}

sub num_required_workers {      # NB: the meaning of this field is, again, "how many extra workers we need to add"
    my $self = shift;
    $self->{'_num_required_workers'} = shift if(@_);
    return $self->{'_num_required_workers'};
}


## dynamic hive_capacity mode attributes:


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


## dynamic hive_capacity mode counters:


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


## other storable ttributes:


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


# non-storable attributes and other helper-methods:


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

sub get_analysis {
    my $self = shift;
    unless($self->{'_analysis'}) {
        $self->{'_analysis'} = $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->analysis_id);
    }
    return $self->{'_analysis'};
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


sub inprogress_job_count {
    my $self = shift;
    return    $self->total_job_count
            - $self->semaphored_job_count
            - $self->ready_job_count
            - $self->done_job_count
            - $self->failed_job_count;
}


sub job_count_breakout {
    my $self = shift;

    my @count_list = ();
    my %count_hash = ();
    my $total_job_count = $self->total_job_count();
    foreach my $count_method (qw(semaphored_job_count ready_job_count inprogress_job_count done_job_count failed_job_count)) {
        if( my $count = $count_hash{$count_method} = $self->$count_method() ) {
            push @count_list, $count.substr($count_method,0,1);
        }
    }
    my $breakout_label = join('+', @count_list);
    $breakout_label .= '='.$total_job_count if(scalar(@count_list)!=1); # only provide a total if multiple or no categories available

    return ($breakout_label, $total_job_count, \%count_hash);
}


sub print_stats {
    my $self = shift @_;

    printf("%-27s(%2d) ",  $self->get_analysis->logic_name, $self->analysis_id );
    print $self->toString."\n";
}


sub toString {
    my $self = shift @_;

    my $analysis = $self->get_analysis;

    my $output = sprintf("%11s jobs(Sem:%d, Rdy:%d, InProg:%d, Done+Pass:%d, Fail:%d)=%d Ave_msec:%d, workers(Running:%d, Reqired:%d) ",
        $self->status,

        $self->semaphored_job_count,
        $self->ready_job_count,
        $self->inprogress_job_count,
        $self->done_job_count,
        $self->failed_job_count,
        $self->total_job_count,

        $self->avg_msec_per_job,

        $self->num_running_workers,
        $self->num_required_workers,
    );
    $output .=  '  h.cap:'    .( defined($self->hive_capacity) ? $self->hive_capacity : '-' )
               .'  a.cap:'    .( defined($analysis->analysis_capacity) ? $analysis->analysis_capacity : '-')
               ."  (sync'd "  .$self->seconds_since_last_update." sec ago)",

    return $output;
}


sub check_blocking_control_rules {
    my $self = shift;
  
    my $ctrl_rules = $self->adaptor->db->get_AnalysisCtrlRuleAdaptor->fetch_all_by_ctrled_analysis_id($self->analysis_id);

    my $all_conditions_satisfied = 1;

    if(scalar @$ctrl_rules) {    # there are blocking ctrl_rules to check

        foreach my $ctrl_rule (@$ctrl_rules) {
                #use this method because the condition_analysis objects can be
                #network distributed to a different database so use it's adaptor to get
                #the AnalysisStats object
            my $condition_analysis  = $ctrl_rule->condition_analysis;
            my $condition_stats     = $condition_analysis && $condition_analysis->stats;
            my $condition_status    = $condition_stats    && $condition_stats->status;
            my $condition_cbe       = $condition_analysis && $condition_analysis->can_be_empty;
            my $condition_tjc       = $condition_stats    && $condition_stats->total_job_count;

            my $this_condition_satisfied = ($condition_status eq 'DONE')
                        || ($condition_cbe && !$condition_tjc);             # probably safer than saying ($condition_status eq 'EMPTY') because of the sync order

            unless( $this_condition_satisfied ) {
                $all_conditions_satisfied = 0;
            }
        }

        if($all_conditions_satisfied) {
            if($self->status eq 'BLOCKED') {    # unblock, since all conditions are met
                $self->update_status('LOADING'); # trigger sync
            }
        } else {    # (re)block
            $self->update_status('BLOCKED');
        }
    }

    return $all_conditions_satisfied;
}


sub determine_status {
    my $self = shift;

    if($self->status ne 'BLOCKED') {
        if( !$self->total_job_count ) {

            $self->status('EMPTY');

        } elsif( $self->total_job_count == $self->done_job_count + $self->failed_job_count ) {   # all jobs of the analysis have been finished
            my $analysis = $self->get_analysis;
            my $absolute_tolerance = $analysis->failed_job_tolerance * $self->total_job_count / 100.0;
            if ($self->failed_job_count > $absolute_tolerance) {
                $self->status('FAILED');
                print "\n##################################################\n";
                printf("##   ERROR: %-35s ##\n", $analysis->logic_name." failed!");
                printf("##     %d jobs failed (tolerance: %d (%3d%%)) ##\n", $self->failed_job_count, $absolute_tolerance, $analysis->failed_job_tolerance);
                print "##################################################\n\n";
            } else {
                $self->status('DONE');
            }
        } elsif( $self->ready_job_count && !$self->inprogress_job_count ) { # there are claimable jobs, but nothing actually running

            $self->status('READY');

        } elsif( !$self->ready_job_count ) {                                # there are no claimable jobs, possibly because some are semaphored

            $self->status('ALL_CLAIMED');

        } elsif( $self->inprogress_job_count ) {

            $self->status('WORKING');
        }
    }
}


1;
