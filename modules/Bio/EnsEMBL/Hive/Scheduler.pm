=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Scheduler

=head1 DESCRIPTION

    Scheduler starts with the numbers of required workers for unblocked analyses,
    then goes through several kinds of restrictions (submit_limit, meadow_limits, hive_capacity, etc)
    that act as limiters and may cap the original numbers in several ways.
    The capped numbers are then grouped by meadow_type and rc_name and returned in a two-level hash.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::Scheduler;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::Limiter;


sub schedule_workers_resync_if_necessary {
    my ($queen, $valley, $filter_analysis) = @_;

    my $meadow_capacity_by_type                 = $valley->get_meadow_capacity_hash_by_meadow_type();

    my $analysis_id2rc_id                       = $queen->db->get_AnalysisAdaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id();
    my $rc_id2name                              = $queen->db->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
        # combined mapping:
    my $analysis_id2rc_name                     = { map { $_ => $rc_id2name->{ $analysis_id2rc_id->{ $_ }} } keys %$analysis_id2rc_id };

    my ($workers_to_submit_by_meadow_type_rc_name, $total_workers_required)
        = schedule_workers($queen, $valley, $filter_analysis, $meadow_capacity_by_type, $analysis_id2rc_name);

    unless( $total_workers_required ) {
        print "\nScheduler: according to analysis_stats no workers are required... let's see if resync can fix it.\n" ;

        if( $queen->count_running_workers() != $valley->count_running_workers ) {
            print "Scheduler: mismatch between Queen's workers and Valley's workers detected, checking for dead workers...\n";
            $queen->check_for_dead_workers($valley, 1);
        }
        print "Scheduler: re-balancing of semaphore_counts...\n";
        $queen->db->get_AnalysisJobAdaptor->balance_semaphores($filter_analysis && $filter_analysis->dbID);
        print "Scheduler: re-synchronizing the Hive...\n";
        $queen->synchronize_hive($filter_analysis);

        ($workers_to_submit_by_meadow_type_rc_name, $total_workers_required)
            = schedule_workers($queen, $valley, $filter_analysis, $meadow_capacity_by_type, $analysis_id2rc_name);
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


sub schedule_workers {
    my ($queen, $valley, $filter_analysis, $meadow_capacity_by_type, $analysis_id2rc_name) = @_;

    my @suitable_analyses   = $filter_analysis
                                ? ( $filter_analysis->stats )
                                : @{ $queen->db->get_AnalysisStatsAdaptor->fetch_all_by_suitability_rc_id_meadow_type() };

    unless(@suitable_analyses) {
        print "Scheduler could not find any suitable analyses to start with\n";
        return ({}, 0);
    }

        # the pre-pending-adjusted outcome will be stored here:
    my %workers_to_submit_by_meadow_type_rc_name    = ();

    my $total_workers_required                      = 0;

    my $default_meadow_type                         = $valley->get_default_meadow()->type;

    my $available_submit_limit                      = $valley->config_get('SubmitWorkersMax');

    my $submit_capacity                             = Bio::EnsEMBL::Hive::Limiter->new( 'Max number of Workers submitted this iteration', $valley->config_get('SubmitWorkersMax') );
    my $queen_capacity                              = Bio::EnsEMBL::Hive::Limiter->new( 'Total reciprocal capacity of the Hive', 1.0 - $queen->get_hive_current_load() );

    foreach my $analysis_stats (@suitable_analyses) {
        last if( $submit_capacity->reached );

        my $analysis            = $analysis_stats->get_analysis;    # FIXME: if it proves too expensive we may need to consider caching
        my $this_meadow_type    = $analysis->meadow_type || $default_meadow_type;

        next if( $meadow_capacity_by_type->{$this_meadow_type}->reached );

            #digging deeper under the surface so need to sync:
        if(($analysis_stats->status eq 'LOADING') or ($analysis_stats->status eq 'BLOCKED') or ($analysis_stats->status eq 'ALL_CLAIMED')) {
            $queen->synchronize_AnalysisStats($analysis_stats);
        }
        next if($analysis_stats->status eq 'BLOCKED');

            # getting the initial worker requirement for this analysis (may be stale if not sync'ed recently)
        my $extra_workers_this_analysis = $analysis_stats->num_required_workers;

            # if this analysis doesn't require any extra workers - just skip it:
        next if ($extra_workers_this_analysis <= 0);

        $total_workers_required += $extra_workers_this_analysis;    # also keep the total number required so far (if nothing required we may need a resync later)

            # setting up all negotiating limiters:
        $queen_capacity->multiplier( $analysis_stats->hive_capacity );
        my @limiters = (
            $submit_capacity,
            $queen_capacity,
            $meadow_capacity_by_type->{$this_meadow_type},
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

        my $this_rc_name    = $analysis_id2rc_name->{ $analysis_stats->analysis_id };
        $workers_to_submit_by_meadow_type_rc_name{ $this_meadow_type }{ $this_rc_name } += $extra_workers_this_analysis;
        $analysis_stats->print_stats();
        printf("Before checking the Valley for pending jobs, Scheduler allocated $extra_workers_this_analysis x $this_meadow_type:$this_rc_name extra workers for '%s' [%.4f hive_load remaining]\n",
            $analysis->logic_name,
            $queen_capacity->available_capacity,
        );
    }

    return (\%workers_to_submit_by_meadow_type_rc_name, $total_workers_required);
}


1;

