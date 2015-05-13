=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Scheduler

=head1 DESCRIPTION

    Scheduler starts with the numbers of required workers for unblocked analyses,
    then goes through several kinds of restrictions (submit_limit, meadow_limits, hive_capacity, etc)
    that act as limiters and may cap the original numbers in several ways.
    The capped numbers are then grouped by meadow_type and rc_name and returned in a two-level hash.

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

=cut


package Bio::EnsEMBL::Hive::Scheduler;

use strict;
use warnings;

use List::Util ('shuffle');

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Limiter;


sub scheduler_say {
    my ($msgs) = @_;

    $msgs = [ $msgs ] unless( ref($msgs) eq 'ARRAY' );

    foreach my $msg (@$msgs) {
        print "Scheduler : $msg\n";
    }
}


sub schedule_workers_resync_if_necessary {
    my ($queen, $valley, $list_of_analyses) = @_;

    my $analysis_id2rc_id                       = $queen->db->get_AnalysisAdaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id();
    my $rc_id2name                              = $queen->db->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
    my $meadow_type_2_name_2_users              = $queen->meadow_type_2_name_2_users_of_running_workers();
        # combined mapping:
    my $analysis_id2rc_name                     = { map { $_ => $rc_id2name->{ $analysis_id2rc_id->{ $_ }} } keys %$analysis_id2rc_id };

    my $submit_capacity                         = $valley->config_get('SubmitWorkersMax');
    my $default_meadow_type                     = $valley->get_default_meadow()->type;
    my ($valley_running_worker_count,
        $meadow_capacity_limiter_hashed_by_type)= $valley->count_running_workers_and_generate_limiters( $meadow_type_2_name_2_users );

    my ($workers_to_submit_by_analysis, $workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer)
        = schedule_workers($queen, $submit_capacity, $default_meadow_type, $list_of_analyses, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name);

    scheduler_say( $log_buffer );

    unless( $total_extra_workers_required ) {
        scheduler_say( "According to analysis_stats no workers are required... let's see if anything went out of sync." );

            # FIXME: here is an (optimistic) assumption all Workers the DB knows about are reachable from the Valley:
        if( $queen->db->get_RoleAdaptor->count_active_roles() != $valley_running_worker_count ) {
            scheduler_say( "Mismatch between DB's active Roles and Valley's running Workers detected, checking for dead workers..." );
            $queen->check_for_dead_workers($valley, 1);
        }

        scheduler_say( "re-synchronizing..." );
        $queen->synchronize_hive( $list_of_analyses );

        if( $queen->db->hive_auto_rebalance_semaphores ) {  # make sure rebalancing only ever happens for the pipelines that asked for it
            if( $queen->check_nothing_to_run_but_semaphored( $list_of_analyses ) ) { # and double-check on our side
                scheduler_say( "looks like we may need re-balancing semaphore_counts..." );
                if( my $rebalanced_jobs_counter = $queen->db->get_AnalysisJobAdaptor->balance_semaphores( $list_of_analyses ) ) {
                    scheduler_say( "re-balanced $rebalanced_jobs_counter jobs, going through another re-synchronization..." );
                    $queen->synchronize_hive( $list_of_analyses );
                } else {
                    scheduler_say( "hmmm... managed to re-balance 0 jobs, you may need to investigate further." );
                }
            } else {
                scheduler_say( "apparently there are no semaphored jobs that may need to be re-balanced at this time." );
            }
        } else {
            scheduler_say( [ "automatic re-balancing of semaphore_counts is off by default.",
                            "If you think your pipeline might benefit from it, set hive_auto_rebalance_semaphores => 1 in the PipeConfig's hive_meta_table." ] );
        }

        ($workers_to_submit_by_analysis, $workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer)
            = schedule_workers($queen, $submit_capacity, $default_meadow_type, $list_of_analyses, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name);

        scheduler_say( $log_buffer );
    }

        # adjustment for pending workers:
    my ($pending_worker_counts_by_meadow_type_rc_name, $total_pending_all_meadows)  = $valley->get_pending_worker_counts_by_meadow_type_rc_name();

    while( my ($this_meadow_type, $partial_workers_to_submit_by_rc_name) = each %$workers_to_submit_by_meadow_type_rc_name) {
        while( my ($this_rc_name, $workers_to_submit_this_group) = each %$partial_workers_to_submit_by_rc_name) {
            if(my $pending_this_group = $pending_worker_counts_by_meadow_type_rc_name->{ $this_meadow_type }{ $this_rc_name }) {

                scheduler_say( "The plan was to submit $workers_to_submit_this_group x $this_meadow_type:$this_rc_name workers when the Scheduler detected $pending_this_group pending in this group, " );

                if( $workers_to_submit_this_group > $pending_this_group) {
                    $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name}   -= $pending_this_group; # adjust the hashed value
                    scheduler_say( "so I recommend submitting only ".$workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name}." extra" );
                } else {
                    delete $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name};                   # avoid leaving an empty group in the hash
                    scheduler_say( "so I don't recommend submitting any extra" );
                }
            } else {
                scheduler_say( "I recommend submitting $workers_to_submit_this_group x $this_meadow_type:$this_rc_name workers" );
            }
        }

        unless(keys %{ $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type} }) {  # if nothing has been scheduled for a meadow,
            delete $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type};          # do not mention the meadow in the hash
        }
    }

    return $workers_to_submit_by_meadow_type_rc_name;
}


sub suggest_analysis_to_specialize_a_worker {
    my ( $worker, $analyses_matching_pattern, $analyses_pattern ) = @_;

    my $queen               = $worker->adaptor;
    my $worker_rc_id        = $worker->resource_class_id;
    my $worker_meadow_type  = $worker->meadow_type;

    if( ! @$analyses_matching_pattern ) {

        return "Could not find any Analyses matching '$analyses_pattern' pattern";

    } else {

        $worker->worker_say( "Found ".scalar(@$analyses_matching_pattern)." analyses matching '$analyses_pattern' pattern" );

        my @analyses_matching_worker = grep { !$worker_rc_id or $worker_rc_id==$_->resource_class_id}
                                        grep { !$worker_meadow_type or !$_->meadow_type or ($worker_meadow_type eq $_->meadow_type) }
                                            # if any other attributes of the worker are specifically constrained in the analysis (such as meadow_name),
                                            # the corresponding checks should be added here
                                                @$analyses_matching_pattern;

        if( !@analyses_matching_worker ) {

            return "Could not find any of the ".scalar(@$analyses_matching_pattern)." '$analyses_pattern' Analyses that would suit this Worker";

        } else {

            my ($workers_to_submit_by_analysis, $workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer)
                = schedule_workers( $queen, 1, $worker_meadow_type, \@analyses_matching_worker );

            if( $worker->debug ) {
                foreach my $msg (@$log_buffer) {
                    $worker->worker_say( $msg );
                }
            }

            return scalar(@$workers_to_submit_by_analysis)
                ? $workers_to_submit_by_analysis->[0][0]    # take the first analysis from the "plan" if the "plan" was not empty
                : pop @$log_buffer;                         # or return the last line of the scheduling log
        }
    }
}


sub schedule_workers {
    my ($queen, $submit_capacity, $default_meadow_type, $list_of_analyses, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name) = @_;

    my @workers_to_submit_by_analysis               = ();   # The down-to-analysis "plan" that may completely change by the time the Workers are born and specialized
    my %workers_to_submit_by_meadow_type_rc_name    = ();   # Pre-pending-adjusted per-resource breakout
    my $total_extra_workers_required                = 0;
    my ($pairs_sorted_by_suitability, $log_buffer)  = Bio::EnsEMBL::Hive::Scheduler::sort_pairs_by_suitability( $list_of_analyses );

    unless( @$pairs_sorted_by_suitability ) {

        unless( @$log_buffer ) {
            push @$log_buffer, "Could not find any suitable analyses to start scheduling.";
        }

    } else {

        my $submit_capacity_limiter = Bio::EnsEMBL::Hive::Limiter->new( 'Max number of Workers scheduled this time', $submit_capacity );
        my $queen_capacity_limiter  = Bio::EnsEMBL::Hive::Limiter->new( 'Total reciprocal capacity of the Hive', 1.0 - $queen->db->get_RoleAdaptor->get_hive_current_load() );

        ANALYSIS: foreach my $pair (@$pairs_sorted_by_suitability) {
            if( $submit_capacity_limiter->reached ) {
                if( $analysis_id2rc_name ) {    # only add this message when scheduling and not during a Worker's specialization
                    push @$log_buffer, "Submission capacity (=".$submit_capacity_limiter->original_capacity.") has been reached.";
                }
                last ANALYSIS;
            }

            my ($analysis, $analysis_stats) = @$pair;

            my $logic_name          = $analysis->logic_name;
            my $this_meadow_type    = $analysis->meadow_type || $default_meadow_type;

            if( $meadow_capacity_limiter_hashed_by_type && $meadow_capacity_limiter_hashed_by_type->{$this_meadow_type}->reached ) {
                push @$log_buffer, "Available capacity of '$this_meadow_type' Meadow (=".$meadow_capacity_limiter_hashed_by_type->{$this_meadow_type}->original_capacity.") has been reached, skipping Analysis '$logic_name'.";
                next ANALYSIS;
            }

                #digging deeper under the surface so need to sync:
            if( $analysis_stats->status =~ /^(LOADING|ALL_CLAIMED|BLOCKED|SYNCHING)$/ ) {
                push @$log_buffer, "Analysis '$logic_name' is ".$analysis_stats->status.", safe-synching it...";

                if( $queen->safe_synchronize_AnalysisStats($analysis_stats) ) {
                    push @$log_buffer, "Safe-sync of Analysis '$logic_name' succeeded.";
                } else {
                    push @$log_buffer, "Safe-sync of Analysis '$logic_name' could not be run at this moment, skipping it.";
                    next ANALYSIS;
                }
            }
            if( $analysis_stats->status =~ /^(BLOCKED|SYNCHING)$/ ) {
                push @$log_buffer, "Analysis '$logic_name' is still ".$analysis_stats->status.", skipping it.";
                next ANALYSIS;
            }

                # getting the initial worker requirement for this analysis (may be off if $analysis_stats has not been sync'ed recently)
            my $extra_workers_this_analysis = $analysis_stats->estimate_num_required_workers;

            if ($extra_workers_this_analysis <= 0) {
                push @$log_buffer, "Analysis '$logic_name' doesn't require extra workers, skipping it.";
                next ANALYSIS;
            }

            $total_extra_workers_required += $extra_workers_this_analysis;    # also keep the total number required so far (if nothing required we may need a resync later)

                # setting up all negotiating limiters:
            $queen_capacity_limiter->multiplier( $analysis_stats->hive_capacity );
            my @limiters = (
                $submit_capacity_limiter,
                $queen_capacity_limiter,
                $meadow_capacity_limiter_hashed_by_type
                    ? $meadow_capacity_limiter_hashed_by_type->{$this_meadow_type}
                    : (),
                defined($analysis->analysis_capacity)
                    ? Bio::EnsEMBL::Hive::Limiter->new( "Number of Workers working at '$logic_name' analysis",
                                                        $analysis->analysis_capacity - $analysis_stats->num_running_workers )
                    : (),
            );

            my $hit_the_limit;

                # negotiations:
            foreach my $limiter (@limiters) {
                ($extra_workers_this_analysis, $hit_the_limit) = $limiter->preliminary_offer( $extra_workers_this_analysis );

                if($hit_the_limit) {
                    if($extra_workers_this_analysis>0) {
                        push @$log_buffer, "Hit the limit of *** ".$limiter->description." ***, settling for $extra_workers_this_analysis Workers.";
                    } else {
                        push @$log_buffer, "Hit the limit of *** ".$limiter->description." ***, skipping this Analysis.";
                        next ANALYSIS;
                    }
                }
            }

                # let all parties know the final decision of negotiations:
            foreach my $limiter (@limiters) {
                $limiter->final_decision( $extra_workers_this_analysis );
            }

            push @workers_to_submit_by_analysis, [ $analysis, $extra_workers_this_analysis];
            push @$log_buffer, $analysis_stats->toString;

            if($analysis_id2rc_name) {
                my $this_rc_name    = $analysis_id2rc_name->{ $analysis_stats->analysis_id };
                $workers_to_submit_by_meadow_type_rc_name{ $this_meadow_type }{ $this_rc_name } += $extra_workers_this_analysis;
                push @$log_buffer, sprintf("Before checking the Valley for pending jobs, the Scheduler allocated $extra_workers_this_analysis x $this_meadow_type:$this_rc_name extra workers for '%s' [%.4f hive_load remaining]",
                                    $logic_name,
                                    $queen_capacity_limiter->available_capacity,
                                );
            }

        }   # /ANALYSIS : foreach my $pair (@$pairs_sorted_by_suitability)
    }

    return (\@workers_to_submit_by_analysis, \%workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer);
}


sub sort_pairs_by_suitability {

    my @sorted_stats    = map { [ $_, $_->stats] }                  # 3. pair analyses with their stats objects
                            sort { $b->priority <=> $a->priority }  # 2. but ordered according to their priority levels
                                shuffle                             # 1. make sure analyses are well mixed within the same priority level
                                    @{ shift @_ };

    my (@primary_candidates, @secondary_candidates, $discarded_count, @log_buffer);

    foreach my $pair ( @sorted_stats ) {
        my ($analysis, $stats) = @$pair;

            # assuming sync() is expensive, so first trying analyses that have already been sunk:
        if( ($stats->estimate_num_required_workers > 0) and ($stats->status =~/^(READY|WORKING)$/) ) {

            push @primary_candidates, $pair;

        } elsif( $stats->status =~ /^(LOADING|BLOCKED|ALL_CLAIMED|SYNCHING)$/ ) {

            push @secondary_candidates, $pair;

        } else {

            $discarded_count++;
        }
    }

    if( $discarded_count ) {
        push @log_buffer, "Discarded $discarded_count analyses because they do not need any Workers.";
    }

    return ( [@primary_candidates,  @secondary_candidates], \@log_buffer );
}

1;

