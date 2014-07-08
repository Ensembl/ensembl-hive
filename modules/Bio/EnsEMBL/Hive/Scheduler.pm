=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Scheduler

=head1 DESCRIPTION

    Scheduler starts with the numbers of required workers for unblocked analyses,
    then goes through several kinds of restrictions (submit_limit, meadow_limits, hive_capacity, etc)
    that act as limiters and may cap the original numbers in several ways.
    The capped numbers are then grouped by meadow_type and rc_name and returned in a two-level hash.

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

=cut


package Bio::EnsEMBL::Hive::Scheduler;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Limiter;


sub schedule_workers_resync_if_necessary {
    my ($queen, $valley, $filter_analysis) = @_;

    my $submit_capacity                         = $valley->config_get('SubmitWorkersMax');
    my $default_meadow_type                     = $valley->get_default_meadow()->type;
    my $meadow_capacity_limiter_hashed_by_type  = $valley->get_meadow_capacity_hash_by_meadow_type();

    my $analysis_id2rc_id                       = $queen->db->get_AnalysisAdaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id();
    my $rc_id2name                              = $queen->db->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
        # combined mapping:
    my $analysis_id2rc_name                     = { map { $_ => $rc_id2name->{ $analysis_id2rc_id->{ $_ }} } keys %$analysis_id2rc_id };

    my ($workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer)
        = schedule_workers($queen, $submit_capacity, $default_meadow_type, undef, undef, $filter_analysis, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name);
    print $log_buffer;

    unless( $total_extra_workers_required ) {
        print "\nScheduler: according to analysis_stats no workers are required... let's see if resync can fix it.\n" ;

            # FIXME: here is an (optimistic) assumption all Workers the DB knows about are reachable from the Valley:
        if( $queen->db->get_RoleAdaptor->count_active_roles() != $valley->count_running_workers ) {
            print "Scheduler: mismatch between DB's active Roles and Valley's running Workers detected, checking for dead workers...\n";
            $queen->check_for_dead_workers($valley, 1);
        }

        print "Scheduler: re-synchronizing the Hive...\n";
        $queen->synchronize_hive($filter_analysis);

        if( $queen->db->hive_auto_rebalance_semaphores ) {  # make sure rebalancing only ever happens for the pipelines that asked for it
            if( $queen->check_nothing_to_run_but_semaphored ) { # and double-check on our side
                print "Scheduler: looks like we may need re-balancing semaphore_counts...\n";
                if( my $rebalanced_jobs_counter = $queen->db->get_AnalysisJobAdaptor->balance_semaphores($filter_analysis && $filter_analysis->dbID) ) {
                    print "Scheduler: re-balanced $rebalanced_jobs_counter jobs, going through another re-synchronization of the Hive...\n";
                    $queen->synchronize_hive($filter_analysis);
                } else {
                    print "Scheduler: hmmm... managed to re-balance 0 jobs, you may need to investigate further.\n";
                }
            } else {
                print "Scheduler: apparently there are no semaphored jobs that may need to be re-balanced at this time.\n";
            }
        } else {
            print "Scheduler: automatic re-balancing of semaphore_counts is off by default. If you think your pipeline might benefit from it, set hive_auto_rebalance_semaphores => 1 in the PipeConfig's hive_meta_table.\n";
        }

        ($workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer)
            = schedule_workers($queen, $submit_capacity, $default_meadow_type, undef, undef, $filter_analysis, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name);
        print $log_buffer;
    }

        # adjustment for pending workers:
    my ($pending_worker_counts_by_meadow_type_rc_name, $total_pending_all_meadows)  = $valley->get_pending_worker_counts_by_meadow_type_rc_name();

    while( my ($this_meadow_type, $partial_workers_to_submit_by_rc_name) = each %$workers_to_submit_by_meadow_type_rc_name) {
        while( my ($this_rc_name, $workers_to_submit_this_group) = each %$partial_workers_to_submit_by_rc_name) {
            if(my $pending_this_group = $pending_worker_counts_by_meadow_type_rc_name->{ $this_meadow_type }{ $this_rc_name }) {

                print "Scheduler was thinking of submitting $workers_to_submit_this_group x $this_meadow_type:$this_rc_name workers when it detected $pending_this_group pending in this group, ";

                if( $workers_to_submit_this_group > $pending_this_group) {
                    $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name}   -= $pending_this_group; # adjust the hashed value
                    print "so is going to submit only ".$workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name}." extra\n";
                } else {
                    delete $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type}{$this_rc_name};                   # avoid leaving an empty group in the hash
                    print "so is not going to submit any extra\n";
                }
            } else {
                print "Scheduler is going to submit $workers_to_submit_this_group x $this_meadow_type:$this_rc_name workers\n";
            }
        }

        unless(keys %{ $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type} }) {  # if nothing has been scheduled for a meadow,
            delete $workers_to_submit_by_meadow_type_rc_name->{$this_meadow_type};          # do not mention the meadow in the hash
        }
    }

    return $workers_to_submit_by_meadow_type_rc_name;
}


sub suggest_analysis_to_specialize_by_rc_id_meadow_type {
    my ($queen, $filter_rc_id, $filter_meadow_type) = @_;

    return schedule_workers($queen, 1, $filter_meadow_type, $filter_rc_id, $filter_meadow_type);
}


sub schedule_workers {
    my ($queen, $submit_capacity, $default_meadow_type, $filter_rc_id, $filter_meadow_type, $filter_analysis, $meadow_capacity_limiter_hashed_by_type, $analysis_id2rc_name) = @_;

    my @suitable_analyses_stats   = $filter_analysis
                                ? ( $filter_analysis->stats )
                                : @{ $queen->db->get_AnalysisStatsAdaptor->fetch_all_by_suitability_rc_id_meadow_type($filter_rc_id, $filter_meadow_type) };

    unless(@suitable_analyses_stats) {
        return $analysis_id2rc_name ? ({}, 0, "Scheduler could not find any suitable analyses to start with\n") : undef;    # FIXME: returns data in different format in "suggest analysis" mode
    }

        # the pre-pending-adjusted outcome will be stored here:
    my %workers_to_submit_by_meadow_type_rc_name    = ();
    my $total_extra_workers_required                = 0;
    my $log_buffer                                  = '';

    my $submit_capacity_limiter                     = Bio::EnsEMBL::Hive::Limiter->new( 'Max number of Workers scheduled this time', $submit_capacity );
    my $queen_capacity_limiter                      = Bio::EnsEMBL::Hive::Limiter->new( 'Total reciprocal capacity of the Hive', 1.0 - $queen->db->get_RoleAdaptor->get_hive_current_load() );

    foreach my $analysis_stats (@suitable_analyses_stats) {
        last if( $submit_capacity_limiter->reached );

        my $analysis            = $analysis_stats->analysis();    # FIXME: if it proves too expensive we may need to consider caching
        my $this_meadow_type    = $analysis->meadow_type || $default_meadow_type;

        next if( $meadow_capacity_limiter_hashed_by_type && $meadow_capacity_limiter_hashed_by_type->{$this_meadow_type}->reached );

            #digging deeper under the surface so need to sync:
        if( $analysis_stats->status =~ /^(LOADING|ALL_CLAIMED|BLOCKED|SYNCHING)$/ ) {
            $queen->safe_synchronize_AnalysisStats($analysis_stats);
        }
        next if( $analysis_stats->status =~ /^(BLOCKED|SYNCHING)$/ );

            # getting the initial worker requirement for this analysis (may be stale if not sync'ed recently)
        my $extra_workers_this_analysis = $analysis_stats->num_required_workers;

            # if this analysis doesn't require any extra workers - just skip it:
        next if ($extra_workers_this_analysis <= 0);

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
                ? Bio::EnsEMBL::Hive::Limiter->new( "Number of Workers working at '".$analysis->logic_name."' analysis",
                                                    $analysis->analysis_capacity - $analysis_stats->num_running_workers )
                : (),
        );

            # negotiations:
        foreach my $limiter (@limiters) {
            $extra_workers_this_analysis = $limiter->preliminary_offer( $extra_workers_this_analysis );
        }

            # do not continue with this analysis if limiters haven't agreed on a positive number:
        next if ($extra_workers_this_analysis <= 0);

            # let all parties know the final decision of negotiations:
        foreach my $limiter (@limiters) {
            $limiter->final_decision( $extra_workers_this_analysis );
        }

        if($analysis_id2rc_name) {
            my $this_rc_name    = $analysis_id2rc_name->{ $analysis_stats->analysis_id };
            $workers_to_submit_by_meadow_type_rc_name{ $this_meadow_type }{ $this_rc_name } += $extra_workers_this_analysis;
            $log_buffer .= $analysis_stats->toString . "\n";
            $log_buffer .= sprintf("Before checking the Valley for pending jobs, Scheduler allocated $extra_workers_this_analysis x $this_meadow_type:$this_rc_name extra workers for '%s' [%.4f hive_load remaining]\n",
                $analysis->logic_name,
                $queen_capacity_limiter->available_capacity,
            );
        } else {
            return $analysis_stats;     # FIXME: returns data in different format in "suggest analysis" mode
        }
    }

    return (\%workers_to_submit_by_meadow_type_rc_name, $total_extra_workers_required, $log_buffer);
}


1;

