#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('destringify');
use Bio::EnsEMBL::Hive::Utils::GraphViz;


my $self = {};

main();

my ($main_pipeline, $start_analysis, $stop_analysis);
my %analysis_name_2_pipeline;

sub main {

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc=i'             => \$self->{'nosqlvc'},             # using "=i" instead of "!" for consistency with scripts where it is a propagated option

        'job_id=s@'             => \$self->{'job_ids'},             # jobs to start from
        'start_analysis_name=s' => \$self->{'start_analysis_name'}, # if given, first trace the graph up to the given analysis or the seed_jobs, and then start visualization
        'stop_analysis_name=s'  => \$self->{'stop_analysis_name'},  # if given, the visualization is aborted at that analysis and doesn't go any further

        'o|out|output=s'        => \$self->{'output'},
        'dot_input=s'           => \$self->{'dot_input'},   # filename to store the intermediate dot input (valuable for debugging)

        'h|help'                => \$self->{'help'},
    );

    if($self->{'url'} or $self->{'reg_alias'}) {
        $main_pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

    } else {
        die "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
    }

    if($self->{'output'}) {

        if(!$self->{'format'}) {
            if($self->{'output'}=~/\.(\w+)$/) {
                $self->{'format'} = $1;
            } else {
                die "Format was not set and could not guess from ".$self->{'output'}.". Please use either way to select it.\n";
            }
        }

        $self->{'graph'} = Bio::EnsEMBL::Hive::Utils::GraphViz->new(
                    'name'          => 'JobDependencyGraph',
                    'concentrate'   => 'true',
                    'pad'           => 1,
        );

        $self->{'graph'}->cluster_2_nodes( {} );
        $self->{'graph'}->cluster_2_colour_pair( {} );
        $self->{'graph'}->display_cluster_names( 1 );

        my $job_adaptor     = $main_pipeline->hive_dba->get_AnalysisJobAdaptor;
        my $anchor_jobs     = $self->{'job_ids'} && $job_adaptor->fetch_all( 'job_id IN ('.join(',', @{$self->{'job_ids'}} ).')' );
        $start_analysis     = $self->{'start_analysis_name'} && $main_pipeline->find_by_query( {'object_type' => 'Analysis', 'logic_name' => $self->{'start_analysis_name'} } );
        $stop_analysis      = $self->{'stop_analysis_name'} && $main_pipeline->find_by_query( {'object_type' => 'Analysis', 'logic_name' => $self->{'stop_analysis_name'} } );

        my $start_jobs  =   $start_analysis
                                ? ( $anchor_jobs
                                        ? find_the_top( $anchor_jobs )                                      # perform a per-jobs scan to the start_analysis
                                        : $job_adaptor->fetch_all_by_analysis_id( $start_analysis->dbID )   # take all jobs of the top analysis
                                ) : ( $anchor_jobs
                                        ? $anchor_jobs                                                      # just start from the given anchor_jobs
                                        : $job_adaptor->fetch_all_by_prev_job_id( undef )                   # by default start from the seed jobs
                                );

        foreach my $start_job ( @$start_jobs ) {
            my $job_node_name   = add_job_node( $start_job );
        }

        foreach my $analysis_name (keys %analysis_name_2_pipeline) {
            my $this_pipeline = $analysis_name_2_pipeline{$analysis_name};
            push @{ $self->{'graph'}->cluster_2_nodes->{ $this_pipeline->hive_pipeline_name } }, $analysis_name;
            $self->{'graph'}->cluster_2_colour_pair->{ $this_pipeline->hive_pipeline_name } = ($this_pipeline == $main_pipeline)
                ? ['pastel19', 3]
                : ['pastel19', 8];
        }

            ## If you need to take a look at the intermediate dot file:
        if( $self->{'dot_input'} ) {
            $self->{'graph'}->dot_input_filename( $self->{'dot_input'} );
        }

        my $call = 'as_'.$self->{'format'};

        $self->{'graph'}->$call($self->{'output'});

    } else {
        die "\nERROR : -output filename has to be defined\n\n";
    }

}


sub find_the_top {
    my ($anchor_jobs) = @_;

    my @starters    = ();

        # first try to find the start_analysis on the way up:
    foreach my $anchor_job ( @$anchor_jobs ) {

        my $job;

        for($job = $anchor_job; (!$start_analysis || ($job->analysis != $start_analysis)) and ($job->prev_job) ; $job = $job->prev_job) {}

        push @starters, $job;
    }

    return \@starters;
}


my %job_node_hash = ();

sub add_job_node {
    my $job = shift @_;

    my $job_id              = $job->dbID;
    my $job_pipeline_name   = $job->hive_pipeline->hive_pipeline_name;
    my $job_node_name       = 'job_'.$job_id.'__'.$job_pipeline_name;

    unless($job_node_hash{$job_node_name}++) {
        my $job_shape           = 'record';
        my $job_status          = $job->status;
        my $job_status_colour   = {'DONE' => 'DeepSkyBlue', 'READY' => 'green', 'SEMAPHORED' => 'grey', 'FAILED' => 'red'}->{$job_status} // 'yellow';
        my $analysis_status_colour = {
            "EMPTY"       => "white",
            "BLOCKED"     => "grey",
            "LOADING"     => "green",
            "ALL_CLAIMED" => "grey",
            "SYNCHING"    => "green",
            "READY"       => "green",
            "WORKING"     => "yellow",
            "DONE"        => "DeepSkyBlue",
            "FAILED"      => "red",
        };

        my $job_id              = $job->dbID;
        my $job_params          = destringify($job->input_id);

        my $job_label           = qq{<<table border="0" cellborder="0" cellspacing="0" cellpadding="1">}
                                 .qq{<tr><td><u><i>job_id:</i></u></td><td><i>$job_id</i></td></tr>};

        if(my $param_id_stack = $job->param_id_stack) {
            $job_label  .=  qq{<tr><td><u><i>params from:</i></u></td><td><i>$param_id_stack</i></td></tr>};
        }

        foreach my $param_key (sort keys %$job_params) {
            my $param_value = $job_params->{$param_key};
            $job_label  .= "<tr><td>$param_key:</td><td> $param_value</td></tr>";
        }

        my $accu_adaptor    = $job->adaptor->db->get_AccumulatorAdaptor;
        my $accu            = $accu_adaptor->fetch_structures_for_job_ids( $job_id )->{ $job_id };

        foreach my $accu_name (sort keys %$accu) {
            $job_label  .=  qq{<tr><td><u><i>accumulated:</i></u></td><td><i>$accu_name</i></td></tr>};
        }

        $job_label  .= "</table>>";


        $self->{'graph'}->add_node( $job_node_name,
            shape       => $job_shape,
            style       => 'filled',
            fillcolor   => $job_status_colour,
            label       => $job_label,
        );

            # adding the job to the corresponding analysis' cluster:
        my $analysis_name   = $job->analysis->relative_display_name($main_pipeline);
        $analysis_name=~s{/}{__};

        my $analysis_status = $job->analysis->status;
        push @{$self->{'graph'}->cluster_2_nodes->{ $analysis_name }}, $job_node_name;
        $self->{'graph'}->cluster_2_colour_pair->{ $analysis_name } = [ $analysis_status_colour->{$analysis_status} ];
        $analysis_name_2_pipeline{ $analysis_name } = $job->hive_pipeline;

            # recursion via child jobs:
        if( !$stop_analysis or ($job->analysis != $stop_analysis) ) {

            my $children = $job->adaptor->fetch_all_by_prev_job_id( $job_id );
            foreach my $child_job ( @$children ) {
                my $child_node_name = add_job_node( $child_job );

                $self->{'graph'}->add_edge( $job_node_name => $child_node_name,
                    color   => 'blue',
                );
            }

            if(my $controlled_semaphore = $job->controlled_semaphore) {
                my $semaphore_node_name = add_semaphore_node( $controlled_semaphore );

                my $parent_is_blocking          = ($job_status eq 'DONE' or $job_status eq 'PASSED_ON') ? 0 : 1;
                my $parent_controlling_colour   = $parent_is_blocking ? 'red' : 'darkgreen';
                my $blocking_arrow              = $parent_is_blocking ? 'tee' : 'none';

                $self->{'graph'}->add_edge( $job_node_name => $semaphore_node_name,
                    color       => $parent_controlling_colour,
                    style       => 'dashed',
                    arrowhead   => $blocking_arrow,
                );
            }
        }
    }

    return $job_node_name;
}


my %semaphore_node_hash = ();

sub add_semaphore_node {
    my $semaphore = shift @_;

    my $semaphore_id                = $semaphore->dbID;
    my $semaphore_pipeline_name     = $semaphore->hive_pipeline->hive_pipeline_name;
    my $semaphore_node_name         = 'semaphore_'.$semaphore_id.'__'.$semaphore_pipeline_name;

    unless($semaphore_node_hash{$semaphore_node_name}++) {

        my $semaphore_blockers          = $semaphore->local_jobs_counter + $semaphore->remote_jobs_counter;
        my $semaphore_is_blocked        = $semaphore_blockers > 0;

        my ($semaphore_colour, $semaphore_shape, $dependent_blocking_arrow_colour, $dependent_blocking_arrow_shape ) = $semaphore_is_blocked
            ? ('red', 'triangle', 'red', 'tee')
            : ('darkgreen', 'invtriangle', 'darkgreen', 'none');

        my @semaphore_label_parts = ();
        if($semaphore_is_blocked) {
            if(my $local=$semaphore->local_jobs_counter) { push @semaphore_label_parts, "local: $local" }
            if(my $remote=$semaphore->remote_jobs_counter) { push @semaphore_label_parts, "remote: $remote" }
        } else {
            push @semaphore_label_parts, "open";
        }
        my $semaphore_label = join("\n", @semaphore_label_parts);

        $self->{'graph'}->add_node( $semaphore_node_name,
            shape       => $semaphore_shape,
            style       => 'filled',
            fillcolor   => $semaphore_colour,
            label       => $semaphore_label,
        );
        
        if(my $dependent_job = $semaphore->dependent_job) {
            my $dependent_job_node_name = add_job_node( $dependent_job );

            $self->{'graph'}->add_edge( $semaphore_node_name => $dependent_job_node_name,
                color       => $dependent_blocking_arrow_colour,
                style       => 'dashed',
                arrowhead   => $dependent_blocking_arrow_shape,
            );

            my $analysis_name   = $dependent_job->analysis->relative_display_name($main_pipeline);
            $analysis_name=~s{/}{__};

                # adding the semaphore node to the cluster of the dependent job's analysis:
            push @{$self->{'graph'}->cluster_2_nodes->{ $analysis_name }}, $semaphore_node_name;
        } elsif(my $dependent_semaphore = $semaphore->dependent_semaphore) {

            my $dependent_semaphore_node_name = add_semaphore_node( $dependent_semaphore );

            $self->{'graph'}->add_edge( $semaphore_node_name => $dependent_semaphore_node_name,
                color       => $dependent_blocking_arrow_colour,
                style       => 'dashed',
                arrowhead   => $dependent_blocking_arrow_shape,
            );

                # adding the semaphore node to its pipeline's cluster:
            push @{$self->{'graph'}->cluster_2_nodes->{ $semaphore->hive_pipeline->hive_pipeline_name }}, $semaphore_node_name;

                # can we trace the local blocking jobs up to their roots?
            my $local_blocker_jobs = $dependent_semaphore->adaptor->db->get_AnalysisJobAdaptor->fetch_all_by_controlled_semaphore_id( $dependent_semaphore->dbID );
            foreach my $start_job ( @{ find_the_top($local_blocker_jobs) } ) {
                my $job_node_name   = add_job_node( $start_job );
            }

        } else {
            die "This semaphore is not blocking anything at all";
        }
    }

    return $semaphore_node_name;
}

