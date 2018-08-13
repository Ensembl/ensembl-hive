=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisStats

=head1 DESCRIPTION

    An object that maintains counters for jobs in different states. This data is used by the Scheduler.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

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

use base ( 'Bio::EnsEMBL::Hive::Storable' );

# How to map the job statuses to the counters
our %status2counter = ('FAILED' => 'failed_job_count', 'READY' => 'ready_job_count', 'DONE' => 'done_job_count', 'PASSED_ON' => 'done_job_count', 'SEMAPHORED' => 'semaphored_job_count');


sub unikey {    # override the default from Cacheable parent
    return [ 'analysis' ];
}


# Minimum amount of time in msec that a worker should run before reporting
# back to the hive. This is also used when deciding how many workers to submit
sub min_worker_runtime {
    return 2*60*1000;
}

sub desired_claim_interval_msec {
    # That's 5 per second
    return 200;
}

# This is the maximum we've seen pipelines reach. In effect, it mostly limits
# the analyses that are fast (i.e. 250 msec per job -> 500 workers at most)
sub max_jobs_per_msec {
    # That's 2000 per second
    return 2;
}

# This is the fastest jobs can be due to the eHive overhead
# It results in eHive scheduling 20 workers to satisfy $self->max_jobs_per_msec
sub min_job_runtime_msec {
    return 10;
}


=head1 AUTOLOADED

    analysis_id / analysis

=cut


sub dbID {
    my $self = shift;

    return $self->analysis_id(@_);
}


sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    return $self->{'_status'};
}

sub is_excluded {
    my $self = shift;
    $self->{'_is_excluded'} = shift if (@_);
    return $self->{'_is_excluded'};
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


## runtime stats:


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
        $self->adaptor->update_stats_and_monitor($self);
    }
}


# Only used by workers
sub get_or_estimate_batch_size {
    my $self                = shift @_;
    my $remaining_job_count = shift @_ || 0;    # FIXME: a better estimate would be $self->claimed_job_count when it is introduced

    my $batch_size = $self->analysis->batch_size;

    if( $batch_size > 0 ) {        # set to positive or not set (and auto-initialized within $self->batch_size)

                                                        # otherwise it is a request for dynamic estimation:
    } elsif( my $avg_msec_per_job = $self->avg_msec_per_job ) {           # further estimations from collected stats

        $batch_size = POSIX::ceil( $self->num_running_workers * $self->desired_claim_interval_msec / $avg_msec_per_job ) || 1;

    } else {        # first estimation when no stats are available (take -$batch_size as first guess, if not zero)
        $batch_size = -$batch_size || 1;
    }

        # TailTrimming correction aims at meeting the requirement half way:
    if( my $num_of_workers = POSIX::ceil( $self->num_running_workers + $self->estimate_num_required_workers($remaining_job_count)/2 ) ) {

        my $jobs_to_do  = $self->ready_job_count + $remaining_job_count;

        my $tt_batch_size = POSIX::floor( $jobs_to_do / $num_of_workers );
        if( (0 < $tt_batch_size) && ($tt_batch_size < $batch_size) ) {
            # More jobs to do than workers and default batch size too large
            $batch_size = $tt_batch_size;
        } elsif(!$tt_batch_size) {
            # Fewer jobs than workers
            $batch_size = POSIX::ceil( $jobs_to_do / $num_of_workers ); # essentially, 0 or 1
        }
    }


    return $batch_size;
}


sub estimate_num_required_workers {     # this doesn't count the workers that are currently running
    my $self                = shift @_;
    my $remaining_job_count = shift @_ || 0;    # FIXME: a better estimate would be $self->claimed_job_count when it is introduced

    # Work left to do
    my $jobs_to_do = $self->ready_job_count + $remaining_job_count;

    # We can assume jobs_to_do>0 i the rest of the function
    return 0 unless $jobs_to_do;

    # Guaranteed to be non-zero
    my $avg_msec_per_job = $self->get_or_estimate_avg_msec_per_job;
    # Number of jobs earmarked for each worker, existing or new. (cannot be zero)
    # NOTE: With the current defaults, this is 12,000 when the analysis has never run
    my $num_jobs_per_worker = POSIX::ceil($self->min_worker_runtime / $avg_msec_per_job );

    # Total number of jobs earmarked for the running workers (knowing they are already running 1 job each)
    # NOTE: This is only greater than zero when jobs are quicker than $self->min_worker_runtime
    my $jobs_for_running_workers = $self->num_running_workers * ($num_jobs_per_worker - 1);

    # NOTE: This means 1 worker per job when jobs_for_running_workers = 0 (no running workers or jobs take more than min_worker_runtime)
    my $num_required_workers = POSIX::ceil( ($jobs_to_do - $jobs_for_running_workers) / $num_jobs_per_worker);
    # NOTE: Since it can be negative when there are fewer jobs to do than what we have earmarked for running workers,
    #       we apply a correction and always submit at least 1 worker (since jobs_to_do is > 0)
    $num_required_workers = 1 if $num_required_workers < 1;

    ## Alternatively
    #if ($jobs_to_do > $jobs_for_running_workers) {
    #    # More jobs than what the existing workers can achieve
    #    $num_required_workers = POSIX::ceil( ($jobs_to_do - $jobs_for_running_workers / 2) / $num_jobs_per_worker);
    #} else {
    #    # In principle all jobs could be done by existing workers, but we still submit some workers in case some workers are stuck
    #    $num_required_workers = POSIX::ceil( ($jobs_to_do / 2) / $num_jobs_per_worker);
    #}

    # 1) hive_capacity
    my $h_cap = $self->analysis->hive_capacity;
    if( defined($h_cap) and $h_cap>=0) {  # what is the currently attainable maximum defined via hive_capacity?
        my $hive_current_load = $self->hive_pipeline->get_cached_hive_current_load();
        my $h_max = POSIX::floor( $h_cap * ( 1.0 - $hive_current_load ) );
        if($h_max < $num_required_workers) {
            $num_required_workers = $h_max;
        }
    }

    # 2) analysis_capacity
    my $a_max = $self->analysis->analysis_capacity;
    if( defined($a_max) and $a_max>=0 ) {   # what is the currently attainable maximum defined via analysis_capacity?
        # Correction for running workers
        $a_max -= $self->num_running_workers;
        if ($a_max <= 0) {
            $num_required_workers = 0;
        } elsif ($a_max < $num_required_workers) {
            $num_required_workers = $a_max;
        }
    }

    # 3) job throughput
    my $t_max = POSIX::floor( $avg_msec_per_job * ($self->max_jobs_per_msec - $self->hive_pipeline->get_total_job_throughput) );
    if($t_max < $num_required_workers) {
        $num_required_workers = $t_max;
    }

    return $num_required_workers;
}


# avg_msec_per_job, or _estimate_avg_msec_per_job, or min_job_runtime_msec
sub get_or_estimate_avg_msec_per_job {
    my $self = shift;

    unless ($self->avg_msec_per_job) {
        unless (exists $self->{'_estimated_avg_msec_per_job'}) {
            $self->{'_estimated_avg_msec_per_job'} = $self->_estimate_avg_msec_per_job;
        }
        return $self->{'_estimated_avg_msec_per_job'} // $self->min_job_runtime_msec;
    }
    return $self->avg_msec_per_job;
}

sub _estimate_avg_msec_per_job {
    my $self = shift;

    return unless $self->num_running_workers;

    # No role has yet been finalized otherwise avg_msec_per_job would be set
    my $active_roles = $self->adaptor->db->get_RoleAdaptor->fetch_all( 'when_finished IS NULL AND analysis_id=' . $self->analysis_id );
    return unless @$active_roles;

    my $tot_lifespan_secs = sum( map {$_->seconds_since_when_started} @$active_roles );
    return unless $tot_lifespan_secs;;

    # Active roles are currently doing a job, which is not yet counted in attempted_jobs
    my $tot_job_attempts = sum( map {$_->attempted_jobs+1} @$active_roles );

    return 1000 * $tot_lifespan_secs / $tot_job_attempts;
}


sub get_job_throughput {
    my $self = shift;

    # Denominator is guaranteed to be non zero
    my $throughput = $self->num_running_workers / $self->get_or_estimate_avg_msec_per_job;
    return $throughput;
}


sub inprogress_job_count {      # includes CLAIMED
    my $self = shift;
    return    $self->total_job_count
            - $self->semaphored_job_count
            - $self->ready_job_count
            - $self->done_job_count
            - $self->failed_job_count;
}


##---------------------------- [stringification] -----------------------------

my %meta_status_2_color = (
    'DONE'      => 'bright_cyan',
    'RUNNING'   => 'bright_yellow',
    'READY'     => 'bright_green',
    'BLOCKED'   => 'black on_white',
    'EMPTY'     => 'clear',
    'FAILED'    => 'red',
);

# "Support for colors 8 through 15 (the bright_ variants) was added in
# Term::ANSIColor 3.00, included in Perl 5.13.3."
# http://perldoc.perl.org/Term/ANSIColor.html#COMPATIBILITY
if ($Term::ANSIColor::VERSION < '3.00') {
    foreach my $s (keys %meta_status_2_color) {
        my $c = $meta_status_2_color{$s};
        $c =~ s/bright_//;
        $meta_status_2_color{$s} = $c;
    }
}

my %analysis_status_2_meta_status = (
    'LOADING'       => 'READY',
    'SYNCHING'      => 'READY',
    'ALL_CLAIMED'   => 'BLOCKED',
    'EXCLUDED'      => 'FAILED',
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
    my $color_enabled = shift;

    return ($color_enabled ? color($meta_status_2_color{$_[1]}).$_[0].color('reset') : $_[0]);
}


sub job_count_breakout {
    my $self = shift;
    my $color_enabled = shift;

    my @count_list = ();
    my %count_hash = ();
    my $total_job_count = $self->total_job_count();
    foreach my $count_method (qw(semaphored_job_count ready_job_count inprogress_job_count done_job_count failed_job_count)) {
        if( my $count = $count_hash{$count_method} = $self->$count_method() ) {
            push @count_list, _text_with_status_color($color_enabled, $count, $count_method_2_meta_status{$count_method}).substr($count_method,0,1);
        }
    }
    my $breakout_label = join('+', @count_list);
    $breakout_label .= '='.$total_job_count if(scalar(@count_list)>1); # only provide a total if multiple categories available
    $breakout_label = '0' if(scalar(@count_list)==0);

    return ($breakout_label, $total_job_count, \%count_hash);
}

sub friendly_avg_job_runtime {
    my $self = shift;
    my $avg  = shift;

    my @units = ([24*3600*1000, 'day'], [3600*1000, 'hr'], [60*1000, 'min'], [1000, 'sec']);

    while (my $unit_description = shift @units) {
        my $x = $avg / $unit_description->[0];
        if ($x >= 1.) {
            return ($x, $unit_description->[1]);
        }
    }
    return ($avg, 'ms');
}


# Very simple interpolation that doesn't need to align the fields
sub toString {
    my $self = shift @_;

    my $fields = $self->_toString_fields;
    my $s = $self->_toString_template;
    # Replace each named field with its value
    $s =~ s/%\((-?)([a-zA-Z_]\w*)\)/$fields->{$2}/ge;
    return $s;
}

sub _toString_template {
    my $self = shift @_;

    return q{%(-logic_name)(%(analysis_id))  %(status),  %(breakout_label) jobs,  avg: %(avg_runtime)%(avg_runtime_unit)  %(num_running_workers) worker%(worker_plural) (%(num_estimated_workers) required),  h.cap:%(hive_capacity) a.cap:%(analysis_capacity)  (sync'd %(seconds_since_when_updated) sec ago)};
}


sub _toString_fields {
    my $self = shift @_;

    my $can_do_colour                                   = (-t STDOUT ? 1 : 0);
    my ($breakout_label, $total_job_count, $count_hash) = $self->job_count_breakout($can_do_colour);
    my $analysis                                        = $self->analysis;
    my $status_text                                     = $self->status;
    if ($self->is_excluded) {
        $status_text = 'EXCLUDED';
    }

    # We don't want to default to min_job_runtime_msec
    my ($avg_runtime, $avg_runtime_unit);
    if ($self->avg_msec_per_job) {
        ($avg_runtime, $avg_runtime_unit) = $self->friendly_avg_job_runtime($self->avg_msec_per_job);
    } elsif ($self->{'_estimated_avg_msec_per_job'}) {
        ($avg_runtime, $avg_runtime_unit) = $self->friendly_avg_job_runtime($self->{'_estimated_avg_msec_per_job'});
    }

    return {
        'logic_name'                    => $analysis->logic_name,
        'analysis_id'                   => $self->analysis_id // 0,
        'status'                        => _text_with_status_color($can_do_colour, $status_text, $analysis_status_2_meta_status{$status_text} || $status_text),
        'breakout_label'                => $breakout_label,
        $avg_runtime_unit ? (                                               ## With trailing characters to have everything look nicely aligned
            'avg_runtime'               => sprintf('%.1f ', $avg_runtime),  # Notice the trailing space
            'avg_runtime_unit'          => $avg_runtime_unit . ',',         # Notice the trailing comma
        ) : (
            'avg_runtime'               => 'N/A,',                          # Notice the trailing commma
            'avg_runtime_unit'          => '',
        ),
        'num_running_workers'           => $self->num_running_workers,
        'worker_plural'                 => $self->num_running_workers != 1 ? 's' : ' ',
        'num_estimated_workers'         => $self->estimate_num_required_workers,
        'hive_capacity'                 => $analysis->hive_capacity // '-',
        'analysis_capacity'             => $analysis->analysis_capacity // '-',
        'seconds_since_when_updated'    => $self->seconds_since_when_updated // 0,
    };
}


##------------------------- [status synchronization] --------------------------


sub check_blocking_control_rules {
    my ($self, $no_die) = @_;
  
    my $ctrl_rules = $self->analysis->control_rules_collection();

    my $all_conditions_satisfied = 1;

    if(scalar @$ctrl_rules) {    # there are blocking ctrl_rules to check

        foreach my $ctrl_rule (@$ctrl_rules) {

            my $condition_analysis  = $ctrl_rule->condition_analysis(undef, $no_die);
            unless ($condition_analysis) {
                $all_conditions_satisfied = 0;
                last
            }

            my $condition_stats     = $condition_analysis->stats;
            unless ($condition_stats) {
                $all_conditions_satisfied = 0;
                last
            }

            # Make sure we use fresh properties of the AnalysisStats object
            # (especially relevant in the case of foreign pipelines, since
            # local objects are periodically refreshed)
            $condition_stats->refresh();

            my $condition_status    = $condition_stats->status;
            my $condition_cbe       = $condition_analysis->can_be_empty;
            my $condition_tjc       = $condition_stats->total_job_count;

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
        foreach my $counter ('semaphored_job_count', 'ready_job_count', 'failed_job_count', 'done_job_count') {
            my $value = sum( map {$job_counts->{$_} // 0} grep {$status2counter{$_} eq $counter} keys %status2counter);
            $self->$counter( $value );
        }
        $self->total_job_count(      sum( values %$job_counts ) || 0 );
    }

    $self->check_blocking_control_rules();

    $self->determine_status();
}


1;
