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
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::TheApiary;
use Bio::EnsEMBL::Hive::Utils ('destringify');
use Bio::EnsEMBL::Hive::Utils::GraphViz;
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

my $self = {};
my ($main_pipeline, $start_analysis, $stop_analysis);
my %analysis_name_2_pipeline;
my %semaphore_url_hash = ();

main();


sub main {

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc'               => \$self->{'nosqlvc'},                 # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option

        'job_id=s@'             => \$self->{'job_ids'},                 # Jobs to start from
        'start_analysis_name=s' => \$self->{'start_analysis_name'},     # if given, first trace the graph up to the given analysis or the seed_jobs, and then start visualisation
        'stop_analysis_name=s'  => \$self->{'stop_analysis_name'},      # if given, the visualisation is aborted at that analysis and doesn't go any further

        'include!'              => \$self->{'include'},                 # if set, include other pipeline rectangles inside the main one
        'suppress_funnel_parent_link!'  => \$self->{'suppress'},        # if set, do not show the link to the parent of a funnel job (potentially less clutter)

        'accu_keys|accus!'      => \$self->{'show_accu_keys'},          # show accu keys, but not necessarily values
        'accu_values|values!'   => \$self->{'show_accu_values'},        # show accu keys & values (implies -accu_keys)
        'accu_pointers|accu_ptrs!' => \$self->{'show_accu_pointers'},   # (attempt to) show which accu values come from which Jobs

        'o|out|output=s'        => \$self->{'output'},                  # output file name
        'f|format=s'            => \$self->{'format'},                  # output format (if not guessable from -output)

        'h|help'                => \$self->{'help'},
    );

    if($self->{'help'}) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    $self->{'show_accu_keys'} = 1 if($self->{'show_accu_values'});      # -accu_values implies -accu_keys

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
                    'pad'           => 0,
                    'ranksep'       => '1.4',
                    'remincross'    => 'true',
        );

        # Defined on its own because it should not be in the dot output but
        # Bio::EnsEMBL::Hive::Utils::GraphViz->new passes all its parameters to dot
        $self->{'graph'}->{'SORT'} = 1;

        $self->{'graph'}->cluster_2_nodes( {} );

            # preload all participating pipeline databases into TheApiary:
        precache_participating_pipelines( $main_pipeline );

        my $job_adaptor     = $main_pipeline->hive_dba->get_AnalysisJobAdaptor;
        my $anchor_jobs     = $self->{'job_ids'} && $job_adaptor->fetch_all( 'job_id IN ('.join(',', @{$self->{'job_ids'}} ).')' );
        $start_analysis     = $self->{'start_analysis_name'} && $main_pipeline->find_by_query( {'object_type' => 'Analysis', 'logic_name' => $self->{'start_analysis_name'} } );
        $stop_analysis      = $self->{'stop_analysis_name'} && $main_pipeline->find_by_query( {'object_type' => 'Analysis', 'logic_name' => $self->{'stop_analysis_name'} } );

        my $start_jobs  = $anchor_jobs
                            ? find_the_top( $anchor_jobs )                                          # scan from $anchor_jobs to start_analysis//top
                            : $start_analysis
                                ? $job_adaptor->fetch_all_by_analysis_id( $start_analysis->dbID )   # take all jobs of the top analysis
                                : find_the_top( $job_adaptor->fetch_all_by_prev_job_id( undef ) );  # scan from seed_jobs to start_analysis//top

        foreach my $start_job ( @$start_jobs ) {
            my $job_node_name   = add_job_node( $start_job );
        }

if(0) {
        for (1..2) {    # a hacky way to get relative independence on sorting order (we don't know the ideal sorting order)
            foreach my $semaphore_url ( keys %semaphore_url_hash ) {
                foreach my $remote_semaphore ( @{ Bio::EnsEMBL::Hive::TheApiary->fetch_remote_semaphores_controlling_this_one( $semaphore_url, $main_pipeline ) } ) {

                    foreach my $start_job ( @{ find_the_top( $remote_semaphore->fetch_my_local_controlling_jobs ) } ) {
                        my $job_node_name   = add_job_node( $start_job );
                    }
                }
            }
        }
}

        foreach my $analysis_name (keys %analysis_name_2_pipeline) {
            my $this_pipeline = $analysis_name_2_pipeline{$analysis_name};
            push @{ $self->{'graph'}->cluster_2_nodes->{ $this_pipeline->hive_pipeline_name } }, $analysis_name;
        }

        my $mcluster_name    = $main_pipeline->hive_pipeline_name;
        $self->{'graph'}->cluster_2_attributes->{ $mcluster_name }{ 'cluster_label' } = $mcluster_name;
        $self->{'graph'}->cluster_2_attributes->{ $mcluster_name }{ 'style' } = 'bold,filled';
        $self->{'graph'}->cluster_2_attributes->{ $mcluster_name }{ 'fill_colour_pair' } = ['pastel19', 3];
        my @other_pipeline_colour_pairs = ( ['pastel19', 8], ['pastel19', 5], ['pastel19', 6], ['pastel19', 1] );

            # now rotate through the list of the non-reference pipelines:
        foreach my $other_pipeline ( @{ Bio::EnsEMBL::Hive::TheApiary->pipelines_except($main_pipeline) } ) {

            my $ocluster_name    = $other_pipeline->hive_pipeline_name;

            my $colour_pair = shift @other_pipeline_colour_pairs;
            $self->{'graph'}->cluster_2_attributes->{ $ocluster_name }{ 'cluster_label' } = $ocluster_name;
            $self->{'graph'}->cluster_2_attributes->{ $ocluster_name }{ 'style' } = 'bold,filled';
            $self->{'graph'}->cluster_2_attributes->{ $ocluster_name }{ 'fill_colour_pair' } = $colour_pair;
            push @other_pipeline_colour_pairs, $colour_pair;

            if($self->{'include'}) {
                push @{ $self->{'graph'}->cluster_2_nodes->{ $mcluster_name } }, $ocluster_name;
            }
        }

        if( $self->{'format'} eq 'dot' ) {          # If you need to take a look at the intermediate dot file
            $self->{'graph'}->dot_input_filename( $self->{'output'} );
            $self->{'graph'}->as_canon( '/dev/null' );

        } else {
            my $call = 'as_'.$self->{'format'};
            $self->{'graph'}->$call($self->{'output'});
        }

    } else {
        die "\nERROR : -output filename has to be defined\n\n";
    }
}


##################### tracing:  ##############################################################################

        # preload all participating pipeline databases into TheApiary:
sub precache_participating_pipelines {
    my @pipelines_to_check = @_;

    my %scanned_pipeline_urls = ();

    while( my $current_pipeline = shift @pipelines_to_check ) {
        my $current_pipeline_url = $current_pipeline->hive_dba->dbc->url;
        unless( $scanned_pipeline_urls{ $current_pipeline_url }++ ) {
            foreach my $df_target ( $current_pipeline->collection_of('DataflowTarget')->list ) {
                    # touching it for the side-effect of loading it to TheApiary:
                my $target_object_pipeline  = $df_target->to_analysis->hive_pipeline;
                my $target_pipeline_url     = $target_object_pipeline->hive_dba->dbc->url;
                unless(exists $scanned_pipeline_urls{$target_pipeline_url}) {
                    push @pipelines_to_check, $target_object_pipeline;
                }
            }
        }
    }
}



sub find_the_top {
    my ($anchor_jobs) = @_;

    my @starters    = ();

        # first try to find the start_analysis on the way up:
    foreach my $anchor_job ( @$anchor_jobs ) {

        push @starters, trace_job_up($anchor_job);

        my $children = $anchor_job->adaptor->fetch_all_by_prev_job_id( $anchor_job->dbID );
        foreach my $child ( @$children ) {
            if( my $semaphore = $child->fetch_local_blocking_semaphore ) {
                push @starters, trace_semaphore_up( $semaphore );
            }
        }
    }

    return \@starters;
}


sub trace_job_up {
    my $job = shift @_;

    my @buffer = ();

    if(my $local_blocking_semaphore = $job->fetch_local_blocking_semaphore) {
        push @buffer, trace_semaphore_up( $local_blocking_semaphore );
    }

    if(my $local_parent_job = $job->prev_job) {
        push @buffer, trace_job_up( $local_parent_job );
    } else {
        push @buffer, $job;
    }

    return @buffer;
}


sub trace_semaphore_up {
    my $semaphore = shift @_;

    my @buffer = ();

    foreach my $local_controlling_job ( @{ $semaphore->fetch_my_local_controlling_jobs } ) {
        push @buffer, trace_job_up( $local_controlling_job );
    }

    foreach my $remote_semaphore ( @{ Bio::EnsEMBL::Hive::TheApiary->fetch_remote_semaphores_controlling_this_one( $semaphore, $main_pipeline ) } ) {
        push @buffer, trace_semaphore_up( $remote_semaphore );
    }

    return @buffer;
}


##################### drawing:  ##############################################################################

sub draw_job_node {
    my ($job, $job_node_name) = @_;

    my $job_shape           = 'box3d';
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

    $job_label  .= "</table>>";


    $self->{'graph'}->add_node( $job_node_name,
        shape       => $job_shape,
        style       => 'filled',
        fillcolor   => $job_status_colour,
        label       => $job_label,
    );

        # adding the job to the corresponding analysis' cluster:
    my $analysis_name   = $job->analysis->relative_display_name($main_pipeline);
    my $cluster_label;

    if($analysis_name =~ m{^(\w+)/(\w+)$}) {
        $analysis_name = $1 . '___' . $2;
        $cluster_label = $2;
    } else {
        $cluster_label = $analysis_name;
    }

    my $analysis_status = $job->analysis->status;
    push @{$self->{'graph'}->cluster_2_nodes->{ $analysis_name }}, $job_node_name;
    $self->{'graph'}->cluster_2_attributes->{ $analysis_name }{ 'cluster_label' } = $cluster_label;
    $self->{'graph'}->cluster_2_attributes->{ $analysis_name }{ 'style' } = 'rounded,filled';
    $self->{'graph'}->cluster_2_attributes->{ $analysis_name }{ 'fill_colour_pair' } = [ $analysis_status_colour->{$analysis_status} ];
    $analysis_name_2_pipeline{ $analysis_name } = $job->hive_pipeline;
}


my %job_node_hash = ();

sub add_job_node {
    my $job = shift @_;

    my $job_id              = $job->dbID;
    my $job_pipeline_name   = $job->hive_pipeline->hive_pipeline_name;
    my $job_node_name       = 'job_'.$job_id.'__'.$job_pipeline_name;

    unless($job_node_hash{$job_node_name}++) {

        draw_job_node( $job, $job_node_name);

            # recursion via child jobs:
        if( !$stop_analysis or ($job->analysis != $stop_analysis) ) {


            my $children = $job->adaptor->fetch_all_by_prev_job_id( $job_id );
            foreach my $child_job ( @$children ) {
                my $child_node_name = add_job_node( $child_job );

                my $child_can_be_controlled = $child_job->fetch_local_blocking_semaphore;

                unless( $self->{'suppress'} and $child_can_be_controlled ) {
                    $self->{'graph'}->add_edge( $job_node_name => $child_node_name,
                        color   => 'blue',
                    );
                }
            }

                # a local semaphore potentially blocked by this job:
            if(my $controlled_semaphore = $job->controlled_semaphore) {
                my $semaphore_node_name = add_semaphore_node( $controlled_semaphore );

                my $job_status                  = $job->status;
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


sub draw_semaphore_and_accu {
    my ($semaphore, $dependent_node_name) = @_;

    my $semaphore_id                = $semaphore->dbID;
    my $semaphore_pipeline_name     = $semaphore->hive_pipeline->hive_pipeline_name;
    my $semaphore_node_name         = 'semaphore_'.$semaphore_id.'__'.$semaphore_pipeline_name;

    my $semaphore_blockers          = $semaphore->local_jobs_counter + $semaphore->remote_jobs_counter;
    my $semaphore_is_blocked        = $semaphore_blockers > 0;
    my $meta_shape                  = $self->{'show_accu_keys'}
                                        ? ['house', 'invhouse' ]            # house shape hints that accu data will be shown if present
                                        : ['triangle', 'invtriangle'];      # triangle shape hints that no accu data will be shown even if present
    my $columns_in_table            = $self->{'show_accu_values'} ? 3 : 2;

    my ($semaphore_shape, $semaphore_bgcolour, $semaphore_fgcolour, $dependent_blocking_arrow_colour, $dependent_blocking_arrow_shape ) = $semaphore_is_blocked
        ? ($meta_shape->[0],    'grey',         'brown',   'red',          'tee')
        : ($meta_shape->[1],    'darkgreen',    'white',   'darkgreen',    'none');

    my @semaphore_label_parts = ();
    if($semaphore_is_blocked) {
        if(my $local=$semaphore->local_jobs_counter) { push @semaphore_label_parts, "local: $local" }
        if(my $remote=$semaphore->remote_jobs_counter) { push @semaphore_label_parts, "remote: $remote" }
    } else {
        push @semaphore_label_parts, "open";
    }
    my $semaphore_label = join(', ', @semaphore_label_parts);

    my $accusem_label  = qq{<<table border="0" cellborder="0" cellspacing="0" cellpadding="1">};
       $accusem_label .= qq{<tr><td colspan="$columns_in_table"><font color="$semaphore_fgcolour"><b><i>$semaphore_label</i></b></font></td></tr>};

    my %accu_ptrs       = ();

    if($self->{'show_accu_keys'}) {
        my $raw_accu_data   = $semaphore->fetch_my_raw_accu_data;

        if(@$raw_accu_data) {
            $accusem_label .= qq{<tr><td colspan="$columns_in_table">&nbsp;</td></tr>};   # skip one table row between semaphore attributes and accu data

            my %struct_name_2_key_signature_and_value = ();
            foreach my $accu_rowhash (@$raw_accu_data) {
                push @{ $struct_name_2_key_signature_and_value{ $accu_rowhash->{'struct_name'} } },
                    [ $accu_rowhash->{'key_signature'}, $accu_rowhash->{'value'}, $accu_rowhash->{'sending_job_id'} ];
            }

            my $sending_job_pipeline_name   = $semaphore->hive_pipeline->hive_pipeline_name;    # assuming cross-database links are currently not stored

            foreach my $struct_name (sort keys %struct_name_2_key_signature_and_value) {
                $accusem_label  .=  $self->{'show_accu_values'}
                    ? qq{<tr><td></td><td><b><u>$struct_name</u></b></td><td></td></tr>}
                    : qq{<tr>         <td><b><u>$struct_name</u></b></td><td></td></tr>};

                my @sorted_values = sort {(($a->[2]//0) <=> ($b->[2]//0)) || ($a->[0] cmp $b->[0]) || ($a->[1] cmp $b->[1])} @{ $struct_name_2_key_signature_and_value{$struct_name} };
                foreach my $accu_vector ( @sorted_values ) {
                    my ($key_signature, $value, $sending_job_id) = @$accu_vector;
                    $sending_job_id //= 0;

                    my $protected_value = $self->{'graph'}->protect_string_for_display($value);
                    my $port_label      = "${semaphore_node_name}_${struct_name}_${sending_job_id}";
                    my $port_attribute  = $sending_job_id ? qq{port="$port_label"} : '';

                    if(my $sending_job_node_name = 'job_'.$sending_job_id.'__'.$sending_job_pipeline_name) {
                        push @{ $accu_ptrs{$sending_job_node_name} }, $port_label;
                    }

                    $accusem_label  .= $self->{'show_accu_values'}
                        ? qq{<tr><td $port_attribute>$key_signature</td><td>&nbsp;<b>--&gt;</b>&nbsp;</td><td>$protected_value</td></tr>}
                        : qq{<tr><td $port_attribute></td><td>$key_signature</td></tr>};
                }
            }
        }
    }

    $accusem_label  .= "</table>>";

    $self->{'graph'}->add_node( $semaphore_node_name,
        shape       => $semaphore_shape,     # 'note',
        margin      => '0,0',
        style       => 'filled',
        fillcolor   => $semaphore_bgcolour,
        label       => $accusem_label,
    );

    if($dependent_node_name) {
        $self->{'graph'}->add_edge( $semaphore_node_name => $dependent_node_name,
            color       => $dependent_blocking_arrow_colour,
            style       => 'dashed',
            arrowhead   => $dependent_blocking_arrow_shape,
            tailport    => 's',
            headport    => 'n',
        );
    }

    if($self->{'show_accu_pointers'}) {
        foreach my $sending_job_node_name (keys %accu_ptrs) {
            foreach my $receiving_port (@{ $accu_ptrs{$sending_job_node_name} }) {

                $self->{'graph'}->add_edge( $sending_job_node_name => $semaphore_node_name,
                    headport    => $receiving_port.':w',
                    color       => 'black',
                    style       => 'dotted',
                );
            }
        }
    }

    return $semaphore_node_name;
}


sub add_semaphore_node {
    my $semaphore = shift @_;

    my $semaphore_url               = $semaphore->relative_url( 0 );    # request for an absolute URL
    my $semaphore_id                = $semaphore->dbID;
    my $semaphore_pipeline_name     = $semaphore->hive_pipeline->hive_pipeline_name;
    my $semaphore_node_name         = 'semaphore_'.$semaphore_id.'__'.$semaphore_pipeline_name;

    unless($semaphore_url_hash{$semaphore_url}++) {

        my ($accu_node_name, $target_cluster_name);

        if(my $dependent_job = $semaphore->dependent_job) {
            my $dependent_job_node_name = add_job_node( $dependent_job );

            $accu_node_name = draw_semaphore_and_accu($semaphore, $dependent_job_node_name);

            $target_cluster_name = $dependent_job->analysis->relative_display_name($main_pipeline);

            if($dependent_job->analysis->hive_pipeline->hive_pipeline_name eq $main_pipeline->hive_pipeline_name) {
                $target_cluster_name =~s{^.*/}{};   # workaround since we may have added $main_pipeline into TheApiary
            } else {
                $target_cluster_name =~s{/}{___};
            }

        } elsif(my $dependent_semaphore = $semaphore->dependent_semaphore) {

            my $dependent_semaphore_node_name = add_semaphore_node( $dependent_semaphore );

            $accu_node_name = draw_semaphore_and_accu($semaphore, $dependent_semaphore_node_name);

            $target_cluster_name = $semaphore->hive_pipeline->hive_pipeline_name;

                # can we trace the local blocking jobs up to their roots?
            foreach my $start_job ( @{ find_the_top( $dependent_semaphore->fetch_my_local_controlling_jobs ) } ) {
                my $job_node_name   = add_job_node( $start_job );
            }

        } else {    # The semaphore is not blocking anything, possibly the end of execution.

            $accu_node_name = draw_semaphore_and_accu($semaphore, undef);

            $target_cluster_name = $semaphore_pipeline_name;
        }

            # adding the semaphore node to the cluster of the dependent job's analysis:
        push @{$self->{'graph'}->cluster_2_nodes->{ $target_cluster_name }}, $semaphore_node_name;
    }

    return $semaphore_node_name;
}


__DATA__

=pod

=head1 NAME

visualize_jobs.pl

=head1 SYNOPSIS

    visualize_jobs.pl -help

    visualize_jobs.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_filename> -reg_alias <reg_alias> ] -output <output_image_filename

=head1 DESCRIPTION

This program generates a visualisation of a subset of interrelated Jobs, Semaphores and Accumulators from a given pipeline database.

Jobs are represented by 3D-rectangles which contain parameters and are colour-coded (reflecting the Job's status).
Semaphores are represented by triangles (red upward-pointing = closed, green downward-pointing = open) which contain the counter.
Accumulators are represented by rectangles with key-paths and may contain data (configurable).

Blue solid arrows show Jobs' parent-child relationships (parents point at their children).
Dashed red lines show Jobs blocking downstream Semaphores.
Dashed green lines show Jobs no longer blocking downstream Semaphores (when the Jobs have finished successfully).
Dashed red/green lines (with colour matching Semaphore's) also link the Semaphores to their Accumulators and further to the controlled Job.

=head1 OPTIONS

=over

=item --url <url>

URL defining where eHive database is located

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_alias <name>

species/alias name for the eHive DBAdaptor

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

=item --job_id <int>

Start with this job(s) and reach as far as possible using parent-child relationships.

=item --start_analysis_name <logic_name>

Trace up to this Analysis and start displaying from this Analysis.

=item --stop_analysis_name <logic_name>

Make this Analysis to be the last one to be displayed.
As the result, the graph may not contain the initial job_id(s).

=item --include

If set, in multi-pipeline contexts include other pipeline rectangles inside the "main" one.
Off by default.

=item --suppress_funnel_parent_link

If set, do not show the link to the parent of a funnel Job (potentially less clutter).
Off by default.

=item --accu_keys

If set, show accu keys in Semaphore nodes.
Off by default.

=item --accu_values

If set, show accu keys & values in Semaphore nodes.
Off by default.

=item --accu_pointers

If set, show an extra link between an item in the accu and the local Job that generated it.
Off by default.

=item --output <path>

Location of the file to write to.
The file extension (.png , .jpeg , .dot , .gif , .ps) will define the output format.

=item --help

Print this help message

=back

=head1 EXTERNAL DEPENDENCIES

=over

=item GraphViz

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

