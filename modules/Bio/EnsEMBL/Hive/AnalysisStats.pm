=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisStats

=head1 DESCRIPTION

    An object that maintains counters for jobs in different states. This data is used by the Scheduler.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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
use Term::ANSIColor;

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

sub when_updated {                   # this method is called by the initial store() [at which point it returns undef]
    my $self = shift;
    $self->{'_when_updated'} = shift if(@_);
    return $self->{'_when_updated'};
}

sub seconds_since_when_updated {     # we fetch the server difference, store local time in the memory object, and use the local difference
    my( $self, $value ) = @_;
    $self->{'_when_updated'} = time() - $value if(defined($value));
    return defined($self->{'_when_updated'}) ? time() - $self->{'_when_updated'} : undef;
}

sub seconds_since_last_fetch {      # track the freshness of the object (store local time, use the local difference)
    my( $self, $value ) = @_;
    $self->{'_last_fetch'} = time() - $value if(defined($value));
    return defined($self->{'_last_fetch'}) ? time() - $self->{'_last_fetch'} : undef;
}

sub sync_lock {
    my $self = shift;
    $self->{'_sync_lock'} = shift if(@_);
    return $self->{'_sync_lock'};
}


# non-storable attributes and other helper-methods:


sub refresh {
    my ($self, $seconds_fresh)      = @_;
    my $seconds_since_last_fetch    = $self->seconds_since_last_fetch;

    if( $self->adaptor
    and (!defined($seconds_fresh) or !defined($seconds_since_last_fetch) or $seconds_fresh < $seconds_since_last_fetch) ) {
        return $self->adaptor->refresh($self);
    }
}


sub update {
    my $self = shift;

    if($self->adaptor) {
        $self->adaptor->update($self);
    }
}


sub get_or_estimate_batch_size {
    my $self                = shift @_;
    my $remaining_job_count = shift @_ || 0;    # FIXME: a better estimate would be $self->claimed_job_count when it is introduced

    my $batch_size = $self->batch_size;

    if( $batch_size > 0 ) {        # set to positive or not set (and auto-initialized within $self->batch_size)

                                                        # otherwise it is a request for dynamic estimation:
    } elsif( my $avg_msec_per_job = $self->avg_msec_per_job ) {           # further estimations from collected stats

        $avg_msec_per_job = 100 if($avg_msec_per_job<100);

        $batch_size = POSIX::ceil( $self->min_batch_time / $avg_msec_per_job );

    } else {        # first estimation when no stats are available (take -$batch_size as first guess, if not zero)
        $batch_size = -$batch_size || 1;
    }

        # TailTrimming correction aims at meeting the requirement half way:
    if( my $num_of_workers = POSIX::ceil( ($self->num_running_workers + $self->estimate_num_required_workers($remaining_job_count))/2 ) ) {

        my $jobs_to_do  = $self->ready_job_count + $remaining_job_count;

        my $tt_batch_size = POSIX::floor( $jobs_to_do / $num_of_workers );
        if( (0 < $tt_batch_size) && ($tt_batch_size < $batch_size) ) {
            $batch_size = $tt_batch_size;
        } elsif(!$tt_batch_size) {
            $batch_size = POSIX::ceil( $jobs_to_do / $num_of_workers ); # essentially, 0 or 1
        }
    }


    return $batch_size;
}


sub estimate_num_required_workers {     # this 'max allowed' total includes the ones that are currently running
    my $self                = shift @_;
    my $remaining_job_count = shift @_ || 0;    # FIXME: a better estimate would be $self->claimed_job_count when it is introduced

    my $num_required_workers = $self->ready_job_count + $remaining_job_count;   # this 'max' estimation can still be zero

    my $h_cap = $self->hive_capacity;
    if( defined($h_cap) and $h_cap>=0) {  # what is the currently attainable maximum defined via hive_capacity?
        my $hive_current_load = $self->adaptor ? $self->adaptor->db->get_RoleAdaptor->get_hive_current_load() : 0;
        my $h_max = $self->num_running_workers + POSIX::floor( $h_cap * ( 1.0 - $hive_current_load ) );
        if($h_max < $num_required_workers) {
            $num_required_workers = $h_max;
        }
    }
    my $a_max = $self->analysis->analysis_capacity;
    if( defined($a_max) and $a_max>=0 ) {   # what is the currently attainable maximum defined via analysis_capacity?
        if($a_max < $num_required_workers) {
            $num_required_workers = $a_max;
        }
    }

    return $num_required_workers;
}


sub inprogress_job_count {      # includes CLAIMED
    my $self = shift;
    return    $self->total_job_count
            - $self->semaphored_job_count
            - $self->ready_job_count
            - $self->done_job_count
            - $self->failed_job_count;
}

my %meta_status_2_color = (
    'DONE'      => 'bright_cyan',
    'RUNNING'   => 'bright_yellow',
    'READY'     => 'bright_green',
    'BLOCKED'   => 'black on_white',
    'EMPTY'     => 'clear',
    'FAILED'    => 'red',
);

my %analysis_status_2_meta_status = (
    'LOADING'       => 'READY',
    'SYNCHING'      => 'READY',
    'ALL_CLAIMED'   => 'BLOCKED',
    'WORKING'       => 'RUNNING',
);

my %count_method_2_meta_status = (
    'semaphored_job_count'  => 'BLOCKED',
    'ready_job_count'       => 'READY',
    'inprogress_job_count'  => 'RUNNING',
    'done_job_count'        => 'DONE',
    'failed_job_count'      => 'FAILED',
);

sub _text_with_status_color {
    my $field_size = shift;
    my $color_enabled = shift;

    my $padding = ($field_size and length($_[0]) < $field_size) ? ' ' x ($field_size - length($_[0])) : '';
    return $padding . ($color_enabled ? color($meta_status_2_color{$_[1]}).$_[0].color('reset') : $_[0]);
}


sub job_count_breakout {
    my $self = shift;
    my $field_size = shift;
    my $color_enabled = shift;

    my $this_length = 0;
    my @count_list = ();
    my %count_hash = ();
    my $total_job_count = $self->total_job_count();
    foreach my $count_method (qw(semaphored_job_count ready_job_count inprogress_job_count done_job_count failed_job_count)) {
        if( my $count = $count_hash{$count_method} = $self->$count_method() ) {
            $this_length += length("$count") + 1;
            push @count_list, _text_with_status_color(undef, $color_enabled, $count, $count_method_2_meta_status{$count_method}).substr($count_method,0,1);
        }
    }
    my $breakout_label = join('+', @count_list);
    $this_length += scalar(@count_list)-1 if @count_list;
    $breakout_label .= '='.$total_job_count if(scalar(@count_list)!=1); # only provide a total if multiple or no categories available
    $this_length += 1+length("$total_job_count") if(scalar(@count_list)!=1);

    $breakout_label = ' ' x ($field_size - $this_length) . $breakout_label if $field_size and $this_length<$field_size;

    return ($breakout_label, $total_job_count, \%count_hash);
}

sub friendly_avg_job_runtime {
    my $self = shift;

    my $avg = $self->avg_msec_per_job;
    my @units = ([24*3600*1000, 'day'], [3600*1000, 'hr'], [60*1000, 'min'], [1000, 'sec']);

    while (my $unit_description = shift @units) {
        my $x = $avg / $unit_description->[0];
        if ($x >= 1.) {
            return ($x, $unit_description->[1]);
        }
    }
    return ($avg, 'ms');
}

sub toString {
    my $self = shift @_;
    my $max_logic_name_length = shift || 40;

    my $can_do_colour                                   = (-t STDOUT ? 1 : 0);
    my ($breakout_label, $total_job_count, $count_hash) = $self->job_count_breakout(24, $can_do_colour);
    my $analysis                                        = $self->analysis;
    my ($avg_runtime, $avg_runtime_unit)                = $self->friendly_avg_job_runtime;

    my $output .= sprintf("%-${max_logic_name_length}s(%3d) %s, jobs( %s ), avg:%5.1f %-3s, workers(Running:%d, Est.Required:%d) ",
        $analysis->logic_name,
        $self->analysis_id // 0,

        _text_with_status_color(11, $can_do_colour, $self->status, $analysis_status_2_meta_status{$self->status} || $self->status),

        $breakout_label,

        $avg_runtime, $avg_runtime_unit,

        $self->num_running_workers,
        $self->estimate_num_required_workers,
    );
    $output .=  '  h.cap:'    .( $self->hive_capacity // '-' )
               .'  a.cap:'    .( $analysis->analysis_capacity // '-')
               ."  (sync'd "  .($self->seconds_since_when_updated // 0)." sec ago)";

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

    $self->check_blocking_control_rules();

    $self->determine_status();
}


1;
