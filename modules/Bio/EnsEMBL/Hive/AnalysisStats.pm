=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisStats

=head1 DESCRIPTION

    An object that maintains counters for jobs in different states. This data is used by the Scheduler.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisStats;

use strict;
use warnings;
use List::Util 'sum';
use POSIX;

use Bio::EnsEMBL::Hive::Utils ('throw');
use Bio::EnsEMBL::Hive::Analysis;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'analysis' ];
}


    ## Minimum amount of time in msec that a worker should run before reporting
    ## back to the hive. This is used when setting the batch_size automatically.
sub min_batch_time {
    return 2*60*1000;
}


=head1 AUTOLOADED

    analysis_id / analysis

=cut


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


## other storable attributes:

sub last_update {                   # this method is called by the initial store() [at which point it returns undef]
    my $self = shift;
    $self->{'_last_update'} = shift if(@_);
    return $self->{'_last_update'};
}

sub seconds_since_last_update {     # this method is mostly used to convert between server time and local time
    my( $self, $value ) = @_;
    $self->{'_last_update'} = time() - $value if(defined($value));
    return defined($self->{'_last_update'}) ? time() - $self->{'_last_update'} : undef;
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

    if($self->adaptor) {
        $self->adaptor->update($self);
    }
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


sub inprogress_job_count {      # includes CLAIMED
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


sub toString {
    my $self = shift @_;

    my $analysis = $self->analysis;

    my $output .= sprintf("%-27s(%2d) %11s jobs(Sem:%d, Rdy:%d, InProg:%d, Done+Pass:%d, Fail:%d)=%d Ave_msec:%d, workers(Running:%d, Reqired:%d) ",
        $analysis->logic_name,
        $self->analysis_id // 0,

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
    $output .=  '  h.cap:'    .( $self->hive_capacity // '-' )
               .'  a.cap:'    .( $analysis->analysis_capacity // '-')
               ."  (sync'd "  .($self->seconds_since_last_update // 0)." sec ago)";

    return $output;
}


sub check_blocking_control_rules {
    my $self = shift;
  
    my $ctrl_rules = $self->analysis->control_rules_collection();

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
                $self->status('LOADING');       # anything that is not 'BLOCKED' will do, it will be redefined in the following subroutine
            }
        } else {    # (re)block
            $self->status('BLOCKED');
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
            my $analysis = $self->analysis;
            my $absolute_tolerance = $analysis->failed_job_tolerance * $self->total_job_count / 100.0;
            if ($self->failed_job_count > $absolute_tolerance) {
                $self->status('FAILED');
                warn       "\n##################################################\n";
                warn sprintf("##   ERROR: %-35s ##\n", $analysis->logic_name." failed!");
                warn sprintf("##     %d jobs failed (tolerance: %d (%3d%%)) ##\n", $self->failed_job_count, $absolute_tolerance, $analysis->failed_job_tolerance);
                warn         "##################################################\n\n";
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


sub recalculate_from_job_counts {
    my ($self, $job_counts) = @_;

        # only update job_counts if given the hash:
    if($job_counts) {
        $self->semaphored_job_count( $job_counts->{'SEMAPHORED'} || 0 );
        $self->ready_job_count(      $job_counts->{'READY'} || 0 );
        $self->failed_job_count(     $job_counts->{'FAILED'} || 0 );
        $self->done_job_count(       ( $job_counts->{'DONE'} // 0 ) + ($job_counts->{'PASSED_ON'} // 0 ) ); # done here or potentially done elsewhere
        $self->total_job_count(      sum( values %$job_counts ) || 0 );
    }

        # compute the number of total required workers for this analysis (taking into account the jobs that are already running)
    my $analysis              = $self->analysis();
    my $scheduling_allowed    =  ( !defined( $self->hive_capacity ) or $self->hive_capacity )
                              && ( !defined( $analysis->analysis_capacity  ) or $analysis->analysis_capacity  );
    my $required_workers    = $scheduling_allowed
                            && POSIX::ceil( $self->ready_job_count() / $self->get_or_estimate_batch_size() );
    $self->num_required_workers( $required_workers );

    $self->check_blocking_control_rules();

    $self->determine_status();
}


1;
