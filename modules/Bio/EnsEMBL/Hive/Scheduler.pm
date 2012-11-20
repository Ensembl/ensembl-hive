=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Scheduler

=head1 DESCRIPTION

    Scheduler starts with the numbers of required workers for unblocked analyses,
    then goes through several kinds of restrictions (submit_limit, meadow_limits, hive_capacity, etc)
    that act as limiters and may cap the original numbers in several ways.
    The capped numbers are then grouped by meadow_type and rc_name and returned in a two-level hash.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::Scheduler;

use strict;
use warnings;

use Clone 'clone';

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::Queen;
use Bio::EnsEMBL::Hive::Valley;


sub schedule_workers_resync_if_necessary {
    my ($queen, $valley, $filter_analysis) = @_;

    my $available_worker_slots_by_meadow_type                                       = $valley->get_available_worker_slots_by_meadow_type();
    my ($pending_worker_counts_by_meadow_type_rc_name, $total_pending_all_meadows)  = $valley->get_pending_worker_counts_by_meadow_type_rc_name();

    my $analysis_id2rc_id         = $queen->db->get_AnalysisAdaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id();
    my $rc_id2name                = $queen->db->get_ResourceClassAdaptor->fetch_HASHED_FROM_resource_class_id_TO_name();
        # combined mapping:
    my $analysis_id2rc_name       = { map { $_ => $rc_id2name->{ $analysis_id2rc_id->{ $_ }} } keys %$analysis_id2rc_id };

    my ($workers_to_submit_by_meadow_type_rc_name, $total_workers_to_submit)
        = schedule_workers($queen, $valley, $filter_analysis, $available_worker_slots_by_meadow_type, $pending_worker_counts_by_meadow_type_rc_name, $analysis_id2rc_name);

    unless( $total_workers_to_submit or $queen->get_hive_current_load() or $queen->count_running_workers() ) {
        print "\nScheduler: nothing is running and nothing to do (according to analysis_stats) => executing garbage collection and sync\n" ;

        $queen->check_for_dead_workers($valley, 1);
        $queen->synchronize_hive($filter_analysis);

        ($workers_to_submit_by_meadow_type_rc_name, $total_workers_to_submit)
            = schedule_workers($queen, $valley, $filter_analysis, $available_worker_slots_by_meadow_type, $pending_worker_counts_by_meadow_type_rc_name, $analysis_id2rc_name);
    }

    return ($workers_to_submit_by_meadow_type_rc_name, $total_workers_to_submit);
}


sub schedule_workers {
    my ($queen, $valley, $filter_analysis, $available_worker_slots_by_meadow_type, $orig_pending_worker_counts_by_meadow_type_rc_name, $analysis_id2rc_name) = @_;

    my @suitable_analyses   = $filter_analysis
                                ? ( $filter_analysis->stats )
                                : @{ $queen->db->get_AnalysisStatsAdaptor->fetch_all_by_suitability_rc_id() };

    unless(@suitable_analyses) {
        print "Scheduler could not find any suitable analyses to start with\n";
        return ({}, 0);
    }

    my %workers_to_submit_by_meadow_type_rc_name    = ();
    my %total_workers_to_submit_by_meadow_type      = ();
    my %pending_worker_counts_by_meadow_type_rc_name= %{ clone $orig_pending_worker_counts_by_meadow_type_rc_name };    # we need a deep disposable copy here
    my $total_workers_to_submit                     = 0;
    my $default_meadow_type                         = $valley->get_default_meadow()->type;
    my $available_submit_limit                      = $valley->config_get('SubmitWorkersMax');
    my $available_load                              = 1.0 - $queen->get_hive_current_load();

    foreach my $analysis_stats (@suitable_analyses) {
        last if ($available_load <= 0.0);

        my $analysis = $analysis_stats->get_analysis();         # FIXME: if it proves too expensive we may need to consider caching

        my $this_meadow_type = $analysis->meadow_type || $default_meadow_type;

        if( defined(my $meadow_limit = $available_worker_slots_by_meadow_type->{ $this_meadow_type }) ) {
            $available_submit_limit = defined($available_submit_limit)
                ? (($available_submit_limit<$meadow_limit) ? $available_submit_limit : $meadow_limit)
                : $meadow_limit;
        }
        last if (defined($available_submit_limit) and !$available_submit_limit);

        #digging deeper under the surface so need to sync
        if(($analysis_stats->status eq 'LOADING') or ($analysis_stats->status eq 'BLOCKED') or ($analysis_stats->status eq 'ALL_CLAIMED')) {
            $queen->synchronize_AnalysisStats($analysis_stats);
        }

        next if($analysis_stats->status eq 'BLOCKED');

        # FIXME: the following call *sometimes* returns a stale number greater than the number of workers actually needed for an analysis; -sync fixes it
        my $workers_this_analysis = $analysis_stats->num_required_workers
            or next;

        if(defined($available_submit_limit)) {                              # available_submit_limit total capping, if available
            if($workers_this_analysis > $available_submit_limit) {
                $workers_this_analysis = $available_submit_limit;
            }
            $available_submit_limit -= $workers_this_analysis;
        }

        if((my $hive_capacity = $analysis_stats->hive_capacity) > 0) {      # per-analysis hive_capacity capping, if available
            my $remaining_capacity_for_this_analysis = int($available_load * $hive_capacity);

            if($workers_this_analysis > $remaining_capacity_for_this_analysis) {
                $workers_this_analysis = $remaining_capacity_for_this_analysis;
            }

            $available_load -= 1.0*$workers_this_analysis/$hive_capacity;
        }

        my $curr_rc_name    = $analysis_id2rc_name->{ $analysis_stats->analysis_id };

        if(my $pending_this_meadow_type_and_rc_name = $pending_worker_counts_by_meadow_type_rc_name{ $this_meadow_type }{ $curr_rc_name }) { # per-rc_name capping by pending processes, if available
            my $pending_this_analysis = ($pending_this_meadow_type_and_rc_name < $workers_this_analysis) ? $pending_this_meadow_type_and_rc_name : $workers_this_analysis;

            print "Scheduler detected $pending_this_analysis pending workers with resource_class_name=$curr_rc_name, adjusting for this value\n";
            $pending_worker_counts_by_meadow_type_rc_name{ $this_meadow_type }{ $curr_rc_name } -= $pending_this_analysis;
            $workers_this_analysis                                                              -= $pending_this_analysis;
        }

        next unless($workers_this_analysis);    # do not autovivify the output hash by a zero

        $workers_to_submit_by_meadow_type_rc_name{ $this_meadow_type }{ $curr_rc_name } += $workers_this_analysis;
        $total_workers_to_submit_by_meadow_type{ $this_meadow_type }                    += $workers_this_analysis;
        $total_workers_to_submit                                                        += $workers_this_analysis;
        $analysis_stats->print_stats();
        printf("Scheduler suggests adding $workers_this_analysis x $this_meadow_type:$curr_rc_name workers for '%s' [%.4f hive_load remaining]\n", $analysis->logic_name, $available_load);
    }

    print ''.('-'x60)."\n";
    foreach my $meadow_type (keys %total_workers_to_submit_by_meadow_type) {
        print "Scheduler suggests submitting a total of $total_workers_to_submit_by_meadow_type{$meadow_type} workers to $meadow_type\n";
    }
    printf("The remaining hive_load after submitting these workers will be: %.4f\n", $available_load);
    print ''.('='x60)."\n";
    return (\%workers_to_submit_by_meadow_type_rc_name, $total_workers_to_submit);
}


1;

