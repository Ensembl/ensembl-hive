=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Graph

=head1 SYNOPSIS

    my $g = Bio::EnsEMBL::Hive::Utils::Graph->new( $hive_pipeline );
    my $graphviz = $g->build();
    $graphviz->as_png('location.png');

=head1 DESCRIPTION

    This is a module for converting a hive database's flow of analyses, control 
    rules and dataflows into the GraphViz model language. This information can
    then be converted to an image or to the dot language for further manipulation
    in GraphViz.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

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


package Bio::EnsEMBL::Hive::Utils::Graph;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::Utils qw(destringify throw);
use Bio::EnsEMBL::Hive::Utils::GraphViz;
use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::TheApiary;

use base ('Bio::EnsEMBL::Hive::Configurable');


=head2 new()

  Arg [1] : Bio::EnsEMBL::Hive::HivePipeline $pipeline;
              The adaptor to get information from
  Arg [2] : (optional) string $config_file_name;
                  A JSON file name to initialize the Config object with.
                  If one is not given then we don't pass anything into Config's constructor,
                  which results in loading configuration from Config's standard locations.
  Returntype : Graph object
  Exceptions : If the parameters are not as required
  Status     : Beta
  
=cut

sub new {
    my $class       = shift @_;
    my $pipeline    = shift @_;

    my $self = bless({}, ref($class) || $class);

    $self->pipeline( $pipeline );

    my $config = Bio::EnsEMBL::Hive::Utils::Config->new( @_ );
    $self->config($config);
    $self->context( [ 'Graph' ] );

    return $self;
}


=head2 graph()

  Arg [1] : The GraphViz instance created by this module
  Returntype : GraphViz
  Exceptions : None
  Status     : Beta

=cut

sub graph {
    my ($self) = @_;

    if(! exists $self->{'_graph'}) {

        $self->{'_graph'} = Bio::EnsEMBL::Hive::Utils::GraphViz->new(
            'name'          => 'AnalysisWorkflow',
            'concentrate'   => 'true',
            'pad'           => $self->config_get('Pad') || 0,
        );

        # Defined on its own because it should not be in the dot output but
        # Bio::EnsEMBL::Hive::Utils::GraphViz->new passes all its parameters to dot
        $self->{'_graph'}->{'SORT'} = 1;
    }
    return $self->{'_graph'};
}


=head2 pipeline()

  Arg [1] : The HivePipeline instance
  Returntype : HivePipeline

=cut

sub pipeline {
    my $self = shift @_;

    if(@_) {
        $self->{'_pipeline'} = shift @_;
    }

    return $self->{'_pipeline'};
}


sub _grouped_dataflow_rules {
    my ($self, $analysis) = @_;

    my $gdr = $self->{'_gdr'} ||= {};

    return $gdr->{$analysis} ||= $analysis->get_grouped_dataflow_rules;
}


sub _analysis_node_name {
    my ($self, $analysis) = @_;

    my $analysis_node_name = 'analysis_' . $analysis->relative_display_name( $self->pipeline );
    if($analysis_node_name=~s/\W/__/g) {
        $analysis_node_name = 'foreign_' . $analysis_node_name;
    }
    return $analysis_node_name;
}


sub _table_node_name {
    my ($self, $naked_table) = @_;

    my $table_node_name = 'table_' . $naked_table->relative_display_name( $self->pipeline );
    $table_node_name=~s/\W/__/g;
    return $table_node_name;
}


sub _accu_sink_node_name {
    my ($funnel_dfr) = @_;

    return 'sink_'.(UNIVERSAL::isa($funnel_dfr, 'Bio::EnsEMBL::Hive::DataflowRule') ? _midpoint_name($funnel_dfr) : ($funnel_dfr || ''));
}


sub _cluster_name {
    my ($df_rule) = @_;

    return ( UNIVERSAL::isa($df_rule, 'Bio::EnsEMBL::Hive::DataflowRule') ? 'cl_'._midpoint_name($df_rule) : ($df_rule || 'cl_noname') );
}


our %_midpoint_ref_to_temp_id;

sub _midpoint_name {
    my ($df_rule) = @_;

    if (UNIVERSAL::isa($df_rule, 'Bio::EnsEMBL::Hive::DataflowRule')) {
        my $dfr_id = $df_rule->dbID || $_midpoint_ref_to_temp_id{scalar($df_rule)};
        unless ($dfr_id) {
            $dfr_id = 'p'.(scalar(keys %_midpoint_ref_to_temp_id) + 1);   # a unique id of a df_rule when dbIDs are not available;
            $_midpoint_ref_to_temp_id{scalar($df_rule)} = $dfr_id;
        }
        return 'dfr_'.$dfr_id.'_mp';
    } else {
        throw("Wrong argument to _midpoint_name");
    }
}


=head2 build()

  Returntype : The GraphViz object built & populated
  Exceptions : Raised if there are issues with accessing the database
  Description : Builds the graph object and returns it.
  Status     : Beta

=cut

sub build {
    my ($self) = @_;

    my $main_pipeline    = $self->pipeline;

    $self->{'_foreign_analyses'} = {};

    foreach my $source_analysis ( @{ $main_pipeline->get_source_analyses } ) {
            # run the recursion in each component that has a non-cyclic start:
        $self->_propagate_allocation( $source_analysis );
    }
    foreach my $cyclic_analysis ( $main_pipeline->collection_of( 'Analysis' )->list ) {
        next if(defined $cyclic_analysis->{'_funnel_dfr'});
        $self->_propagate_allocation( $cyclic_analysis );
    }

    foreach my $source_analysis ( @{ $main_pipeline->get_source_analyses } ) {
            # run the recursion in each component that has a non-cyclic start:
        $self->_add_analysis_node( $source_analysis );
    }
    foreach my $cyclic_analysis ( $main_pipeline->collection_of( 'Analysis' )->list ) {
        next if($self->{'_created_analysis'}{ $cyclic_analysis });
        $self->_add_analysis_node( $cyclic_analysis );
    }

    if($self->config_get('DisplayStretched') ) {    # put each analysis before its' funnel midpoint
        foreach my $analysis ( $main_pipeline->collection_of('Analysis')->list ) {
            if(ref($analysis->{'_funnel_dfr'})) {    # this should only affect analyses that have a funnel
                my $from = $self->_analysis_node_name( $analysis );
                my $to   = _midpoint_name( $analysis->{'_funnel_dfr'} );
                $self->graph->add_edge( $from => $to,
                    style     => 'invis',   # toggle visibility by changing 'invis' to 'dashed'
                    color     => 'black',
                );
            }
        }
    }

    my %cluster_2_nodes = ();
    $self->graph->cluster_2_nodes( \%cluster_2_nodes );

    if( $self->config_get('DisplayDetails') ) {
        foreach my $pipeline ( Bio::EnsEMBL::Hive::TheApiary->pipelines_collection->list ) {
            my $pipeline_cluster_name   = _cluster_name( $pipeline->hive_pipeline_name );
            $self->graph->cluster_2_attributes->{ $pipeline_cluster_name }{ 'cluster_label' } = $pipeline_cluster_name;
            $self->graph->cluster_2_attributes->{ $pipeline_cluster_name }{ 'style' } = 'bold,filled';

            $self->graph->cluster_2_attributes->{ $pipeline_cluster_name }{ 'fill_colour_pair' } = ($pipeline == $main_pipeline)
                ? [$self->config_get('Box', 'MainPipeline', 'ColourScheme'),  $self->config_get('Box', 'MainPipeline', 'ColourOffset')]
                : [$self->config_get('Box', 'OtherPipeline', 'ColourScheme'), $self->config_get('Box', 'OtherPipeline', 'ColourOffset')];
        }
    }

    if($self->config_get('DisplaySemaphoreBoxes') ) {
        foreach my $analysis ( $main_pipeline->collection_of('Analysis')->list, values %{ $self->{'_foreign_analyses'} } ) {

            push @{$cluster_2_nodes{ _cluster_name( $analysis->{'_funnel_dfr'} ) } }, $self->_analysis_node_name( $analysis );

            foreach my $group ( @{ $self->_grouped_dataflow_rules($analysis) } ) {

                my ($df_rule, $fan_dfrs, $df_targets) = @$group;

                my $choice      = (scalar(@$df_targets)!=1) || defined($df_targets->[0]->on_condition);

                if(@$fan_dfrs or $choice) {
                        # top-level funnels define clusters (top-level "boxes"):
                    push @{$cluster_2_nodes{ _cluster_name( $df_rule->{'_funnel_dfr'} ) }}, _midpoint_name( $df_rule );

                    my $box_needed = 0;
                    foreach my $fan_dfr (@$fan_dfrs) {
                        my $fan_targets = $fan_dfr->get_my_targets; # FIXME: ->get_my_targets() may be too computationally-expensive to run so may times?
                        foreach my $fan_target (@$fan_targets) {
                            my $target_object = $fan_target->to_analysis;
                            if( $target_object->{'_funnel_dfr'} eq $df_rule
#                            or  $target_object->hive_pipeline ne $fan_dfr->hive_pipeline    # crossing the pipeline boundary
                            ) {
                                $box_needed = 1;
                            }
                        }
                    }
                    if( $box_needed ) {
                        push @{$cluster_2_nodes{ _cluster_name( $df_rule->{'_funnel_dfr'} ) }}, _cluster_name( $df_rule );
                    }

                    foreach my $fan_dfr (@$fan_dfrs) {
                        push @{$cluster_2_nodes{ _cluster_name( $fan_dfr->{'_funnel_dfr'} ) } }, _midpoint_name( $fan_dfr ); # midpoints of rules that have a funnel live inside "boxes"
                    }
                }

                foreach my $df_target (@$df_targets) {
                    my $target_object = $df_target->to_analysis;
                    if( UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable') ) {        # put the table into the same "box" as the dataflow source:

                        push @{$cluster_2_nodes{ _cluster_name( $target_object->{'_funnel_dfr'} ) } }, $self->_table_node_name( $target_object );

                    } elsif( UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator') ) {  # put the accu sink into the same "box" as the dataflow source:

                        push @{$cluster_2_nodes{ _cluster_name( $analysis->{'_funnel_dfr'} ) } }, _accu_sink_node_name( $analysis->{'_funnel_dfr'} );
                    }
                }
            } # /foreach group
        }

        $self->graph->nested_bgcolour( [$self->config_get('Box', 'Semaphore', 'ColourScheme'),     $self->config_get('Box', 'Semaphore', 'ColourOffset')] );
    }

    return $self->graph();
}


sub _propagate_allocation {
    my ($self, $source_object, $curr_allocation ) = @_;

    $curr_allocation ||= $source_object->hive_pipeline->hive_pipeline_name;

    if(!exists $source_object->{'_funnel_dfr'} ) {     # only allocate on the first-come basis:
        $source_object->{'_funnel_dfr'} = $curr_allocation;

        if(UNIVERSAL::isa($source_object, 'Bio::EnsEMBL::Hive::Analysis')) {

            foreach my $group ( @{ $self->_grouped_dataflow_rules($source_object) } ) {

                my ($df_rule, $fan_dfrs, $df_targets) = @$group;

                $df_rule->{'_funnel_dfr'} = $curr_allocation;

                foreach my $df_target (@$df_targets) {
                    my $target_object       = $df_target->to_analysis;

                        #   In case we have crossed pipeline borders, let the next call decide its own allocation by resetting it.
                    $self->_propagate_allocation( $target_object, ($source_object->hive_pipeline == $target_object->hive_pipeline) ? $curr_allocation : '' );
                }

                    # all fan members point to the funnel.
                    #   Request midpoint's allocation since we definitely have a funnel to link to.
                foreach my $fan_dfr (@$fan_dfrs) {
                    $fan_dfr->{'_funnel_dfr'} = $curr_allocation;

                    foreach my $df_target (@{ $fan_dfr->get_my_targets }) {
                        my $fan_target_object = $df_target->to_analysis;

                        $self->_propagate_allocation( $fan_target_object, ($source_object->hive_pipeline == $fan_target_object->hive_pipeline) ? $df_rule : '' );
                    }
                }

            } # /foreach group
        } # if source_object isa Analysis
    }
}


sub _add_analysis_node {
    my ($self, $analysis) = @_;

    my $this_analysis_node_name                           = $self->_analysis_node_name( $analysis );

    return $this_analysis_node_name if($self->{'_created_analysis'}{ $analysis }++);   # making sure every Analysis node gets created no more than once

    my $analysis_stats = $analysis->stats();

    my ($breakout_label, $total_job_count, $count_hash)   = $analysis_stats->job_count_breakout();
    my $analysis_status                                   = $analysis_stats->status;
    my $analysis_status_colour                            = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Colour');
    my $analysis_shape                                    = $self->config_get('Node', 'AnalysisStatus', 'Shape');
    my $analysis_style                                    = $analysis->can_be_empty() ? 'dashed, filled' : 'filled' ;
    my $node_fontname                                     = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Font');
    my $display_stats                                     = $self->config_get('DisplayStats');
    my $display_dbIDs                                     = $self->config_get('DisplayDBIDs');
    my $hive_pipeline                                     = $self->pipeline;

    my $colspan = 0;
    my $bar_chart = '';

    if( $display_stats eq 'barchart' ) {
        foreach my $count_method (qw(SEMAPHORED READY INPROGRESS DONE FAILED)) {
            if(my $count=$count_hash->{lc($count_method).'_job_count'}) {
                $bar_chart .= '<td bgcolor="'.$self->config_get('Node', 'JobStatus', $count_method, 'Colour').'" width="'.int(100*$count/$total_job_count).'%">'.$count.lc(substr($count_method,0,1)).'</td>';
                ++$colspan;
            }
        }
        if($colspan != 1) {
            $bar_chart .= '<td>='.$total_job_count.'</td>';
            ++$colspan;
        }
    }

    $colspan ||= 1;
    my $analysis_label  = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.$colspan.'">'.$analysis->relative_display_name( $hive_pipeline ).($display_dbIDs ? ' ('.($analysis->dbID || 'unstored').')' : '').'</td></tr>';
    if( $display_stats ) {
        $analysis_label    .= qq{<tr><td colspan="$colspan"> </td></tr>};
        if( $display_stats eq 'barchart') {
            $analysis_label    .= qq{<tr>$bar_chart</tr>};
        } elsif( $display_stats eq 'text') {
            $analysis_label    .= qq{<tr><td colspan="$colspan">$breakout_label</td></tr>};
        }
    }

    if( my $job_limit = $self->config_get('DisplayJobs') ) {
        my $display_job_length = $self->config_get('DisplayJobLength');

        if(my $job_adaptor = $analysis->adaptor && $analysis->adaptor->db->get_AnalysisJobAdaptor) {
            my @jobs = sort {$a->dbID <=> $b->dbID} @{ $job_adaptor->fetch_some_by_analysis_id_limit( $analysis->dbID, $job_limit+1 )};
            $analysis->jobs_collection( \@jobs );
        }

        my @jobs = @{ $analysis->jobs_collection };

        my $hit_limit;
        if(scalar(@jobs)>$job_limit) {
            pop @jobs;
            $hit_limit = 1;
        }

        $analysis_label    .= '<tr><td colspan="'.$colspan.'"> </td></tr>';
        foreach my $job (@jobs) {
            my $input_id = $self->graph->protect_string_for_display( $job->input_id, $display_job_length, 1 );
            my $status   = $job->status;
            my $job_id   = $job->dbID || 'unstored';

            $analysis_label    .= qq{<tr><td align="left" colspan="$colspan" bgcolor="}.$self->config_get('Node', 'JobStatus', $status, 'Colour').qq{">$job_id [$status]: $input_id</td></tr>};
        }

        if($hit_limit) {
            $analysis_label    .= qq{<tr><td colspan="$colspan">[ + }.($total_job_count-$job_limit).qq{ more jobs ]</td></tr>};
        }
    }
    $analysis_label    .= '</table>>';
  
    $self->graph->add_node( $this_analysis_node_name,
        shape       => $analysis_shape,
        style       => $analysis_style,
        fillcolor   => $analysis_status_colour,
        fontname    => $node_fontname,
        label       => $analysis_label,
    );

    $self->_add_control_rules( $analysis->control_rules_collection );
    $self->_add_dataflow_rules( $analysis );

    return $this_analysis_node_name;
}


sub _add_accu_sink_node {
    my ($self, $funnel_dfr) = @_;

    my $accusink_shape      = $self->config_get('Node', 'AccuSink', 'Shape');
    my $accusink_style      = $self->config_get('Node', 'AccuSink', 'Style');
    my $accusink_colour     = $self->config_get('Node', 'AccuSink', 'Colour');
    my $accusink_font       = $self->config_get('Node', 'AccuSink', 'Font');
    my $accusink_fontcolour = $self->config_get('Node', 'AccuSink', 'FontColour');

    my $accu_sink_node_name = _accu_sink_node_name( $funnel_dfr );

    $self->graph->add_node( $accu_sink_node_name,
        style       => $accusink_style,
        shape       => $accusink_shape,
        fillcolor   => $accusink_colour,
        fontname    => $accusink_font,
        fontcolor   => $accusink_fontcolour,
        label       => 'Accu',
    );

    return $accu_sink_node_name;
}


sub _add_control_rules {
    my ($self, $ctrl_rules) = @_;

    my $control_colour = $self->config_get('Edge', 'Control', 'Colour');
    my $graph = $self->graph();

        #The control rules are always from and to an analysis so no need to search for odd cases here
    foreach my $c_rule ( @$ctrl_rules ) {
        my $condition_analysis  = $c_rule->condition_analysis;
        my $ctrled_analysis     = $c_rule->ctrled_analysis;

        my $ctrled_is_local     = $ctrled_analysis->is_local_to( $self->pipeline );
        my $condition_is_local  = $condition_analysis->is_local_to( $self->pipeline );

        if($ctrled_is_local and !$condition_is_local) {     # register a new "near neighbour" node if it's reachable by following one rule "out":
            $self->{'_foreign_analyses'}{ $condition_analysis->relative_display_name($self->pipeline) } = $condition_analysis;
        }

        next unless( $ctrled_is_local or $condition_is_local or $self->{'_foreign_analyses'}{ $condition_analysis->relative_display_name($self->pipeline) } );

        my $from_node_name      = $self->_analysis_node_name( $condition_analysis );
        my $to_node_name        = $self->_analysis_node_name( $ctrled_analysis );

        $graph->add_edge( $from_node_name => $to_node_name,
            color => $control_colour,
            arrowhead => 'tee',
        );
    }
}


sub _last_part_arrow {
    my ($self, $from_analysis, $source_node_name, $label_prefix, $df_target, $extras) = @_;

    my $graph               = $self->graph();
    my $dataflow_colour     = $self->config_get('Edge', 'Data', 'Colour');
    my $accu_colour         = $self->config_get('Edge', 'Accu', 'Colour');
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');

    my $target_object       = $df_target->to_analysis;
    my $target_node_name    =
            UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')      ? $self->_add_analysis_node( $target_object )
        :   UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')    ? $self->_add_table_node( $target_object )
        :   UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')   ? $self->_add_accu_sink_node( $from_analysis->{'_funnel_dfr'} )
        :   die "Unknown node type";

    if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {    # skip some *really* foreign dataflow rules:

        my $from_is_local   = $from_analysis->is_local_to( $self->pipeline );
        my $target_is_local = $target_object->is_local_to( $self->pipeline );

        if($from_is_local and !$target_is_local) {  # register a new "near neighbour" node if it's reachable by following one rule "out":
            $self->{'_foreign_analyses'}{ $target_object->relative_display_name($self->pipeline) } = $target_object;
        }

        return unless( $from_is_local or $target_is_local or $self->{'_foreign_analyses'}{ $target_object->relative_display_name($self->pipeline) } );
    }

    my $input_id_template   = $self->config_get('DisplayInputIDTemplate') ? $df_target->input_id_template : undef;
    my $extend_param_stack  = $df_target->extend_param_stack;
    my $multistring_template= ($extend_param_stack ? "INPUT_PLUS " : '')
                             .($input_id_template  ?  '{'.join(",\n", sort keys( %{destringify($input_id_template)} )).'}'
                                                   : ($extend_param_stack ? '' : '') );

    $graph->add_edge( $source_node_name => $target_node_name,
        @$extras,
        UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')
            ? (
                color       => $accu_colour,
                fontcolor   => $accu_colour,
                style       => 'dashed',
                dir         => 'both',
                arrowtail   => 'crow',
                label       => $label_prefix."\n=> ".$target_object->relative_display_name( $self->pipeline ),
            ) : (
                color       => $dataflow_colour,
                fontcolor   => $dataflow_colour,
                label       => $label_prefix."\n".$multistring_template,
            ),
        fontname    => $df_edge_fontname,
    );
}


sub _twopart_arrow {
    my ($self, $df_rule, $df_targets) = @_;

    my $graph               = $self->graph();
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');
    my $switch_shape        = $self->config_get('Node', 'Switch', 'Shape');
    my $switch_style        = $self->config_get('Node', 'Switch', 'Style');
    my $switch_colour       = $self->config_get('Node', 'Switch', 'Colour');
    my $switch_font         = $self->config_get('Node', 'Switch', 'Font');
    my $switch_fontcolour   = $self->config_get('Node', 'Switch', 'FontColour');
    my $display_cond_length = $self->config_get('DisplayConditionLength');

    my $from_analysis       = $df_rule->from_analysis;
    my $from_node_name      = $self->_analysis_node_name( $from_analysis );
    my $midpoint_name       = _midpoint_name( $df_rule );

       $df_targets        ||= $df_rule->get_my_targets;
    my $choice              = (scalar(@$df_targets)!=1) || defined($df_targets->[0]->on_condition);
    my $tablabel            = qq{<<table border="0" cellborder="0" cellspacing="0" cellpadding="1">i<tr><td></td></tr>};

    my $targets_grouped_by_condition = $df_rule->get_my_targets_grouped_by_condition( $df_targets );

    foreach my $i (0..scalar(@$targets_grouped_by_condition)-1) {

        my $condition = $targets_grouped_by_condition->[$i]->[0];

        if(defined($condition)) {
            $condition = $display_cond_length
                       ? $graph->protect_string_for_display( $condition, $display_cond_length )   # trim and protect it
                       : 'condition_'.$i;                                           # override it completely with a numbered label
        }
        $tablabel .= qq{<tr><td port="cond_$i">}.((defined $condition) ? "WHEN $condition" : $choice ? 'ELSE' : '')."</td></tr>";
    }
    $tablabel .= '</table>>';

    $graph->add_node( $midpoint_name,   # midpoint itself
        $choice ? (
            shape       => $switch_shape,
            style       => $switch_style,
            fillcolor   => $switch_colour,
            fontname    => $switch_font,
            fontcolor   => $switch_fontcolour,
            label       => $tablabel,
        ) : (
            shape       => 'point',
            fixedsize   => 1,
            width       => 0.01,
            height      => 0.01,
        ),
    );
    $graph->add_edge( $from_node_name => $midpoint_name, # first half of the two-part arrow
        color       => 'black',
        fontcolor   => 'black',
        fontname    => $df_edge_fontname,
        label       => '#'.$df_rule->branch_code,
        headport    => 'n',
        $choice ? (
            arrowhead   => 'normal',
        ) : (
            arrowhead   => 'none',
        ),
    );

    foreach my $i (0..scalar(@$targets_grouped_by_condition)-1) {

        my $target_group = $targets_grouped_by_condition->[$i]->[1];

        foreach my $df_target (@$target_group) {
            $self->_last_part_arrow($from_analysis, $midpoint_name, '', $df_target, $choice ? [ tailport => "cond_$i" ] : [ tailport => 's' ]);
        }
    }

    return $midpoint_name;
}


sub _add_dataflow_rules {
    my ($self, $from_analysis) = @_;

    my $graph               = $self->graph();
    my $semablock_colour    = $self->config_get('Edge', 'Semablock', 'Colour');

    foreach my $group ( @{ $self->_grouped_dataflow_rules($from_analysis) } ) {

        my ($df_rule, $fan_dfrs, $df_targets) = @$group;

        if(@$fan_dfrs) {    # semaphored funnel case => all rules have an Analysis target and have two parts:

            my $funnel_midpoint_name = $self->_twopart_arrow( $df_rule, $df_targets );

            foreach my $fan_dfr (@$fan_dfrs) {
                my $fan_midpoint_name = $self->_twopart_arrow( $fan_dfr );

                    # add a semaphore inter-rule blocking arc:
                $graph->add_edge( $fan_midpoint_name => $funnel_midpoint_name,
                    color     => $semablock_colour,
                    style     => 'dashed',
                    dir       => 'both',
                    arrowhead => 'tee',
                    arrowtail => 'crow',
                );
            }

        } else {
            my $choice      = (scalar(@$df_targets)!=1) || defined($df_targets->[0]->on_condition);

            if($choice) {
                $self->_twopart_arrow( $df_rule, $df_targets );
            } else {
                my $from_node_name  = $self->_analysis_node_name( $from_analysis );
                my $df_target       = $df_targets->[0];

                $self->_last_part_arrow($from_analysis, $from_node_name, '#'.$df_rule->branch_code, $df_target, []);
            }
        }

    } # /foreach my $group
}


sub _add_table_node {
    my ($self, $naked_table) = @_;

    my $table_shape             = $self->config_get('Node', 'Table', 'Shape');
    my $table_style             = $self->config_get('Node', 'Table', 'Style');
    my $table_colour            = $self->config_get('Node', 'Table', 'Colour');
    my $table_header_colour     = $self->config_get('Node', 'Table', 'HeaderColour');
    my $table_fontcolour        = $self->config_get('Node', 'Table', 'FontColour');
    my $table_fontname          = $self->config_get('Node', 'Table', 'Font');

    my $hive_pipeline           = $self->pipeline;
    my $this_table_node_name    = $self->_table_node_name( $naked_table );

    my (@column_names, $columns, $table_data, $data_limit, $hit_limit);

    if( $data_limit = $self->config_get('DisplayData') and my $naked_table_adaptor = $naked_table->adaptor ) {

        @column_names = sort keys %{$naked_table_adaptor->column_set};
        $columns = scalar(@column_names);
        $table_data = $naked_table_adaptor->fetch_all( 'LIMIT '.($data_limit+1) );

        if(scalar(@$table_data)>$data_limit) {
            pop @$table_data;
            $hit_limit = 1;
        }
    }

    my $table_label = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.($columns||1).'">'. $naked_table->relative_display_name( $hive_pipeline ) .'</td></tr>';

    if( $data_limit and $columns) {
        my $display_column_length = $self->config_get('DisplayColumnLength');

        $table_label .= '<tr><td colspan="'.$columns.'"> </td></tr>';
        $table_label .= '<tr>'.join('', map { qq{<td bgcolor="$table_header_colour" border="1">$_</td>} } @column_names).'</tr>';
        foreach my $row (@$table_data) {
            $table_label .= '<tr>'.join('', map { '<td>'.$self->graph->protect_string_for_display($_,  $display_column_length).'</td>' } @{$row}{@column_names}).'</tr>';
        }
        if($hit_limit) {
            $table_label  .= qq{<tr><td colspan="$columns">[ more data ]</td></tr>};
        }
    }
    $table_label .= '</table>>';

    $self->graph()->add_node( $this_table_node_name,
        shape       => $table_shape,
        style       => $table_style,
        fillcolor   => $table_colour,
        fontname    => $table_fontname,
        fontcolor   => $table_fontcolour,
        label       => $table_label,
    );

    return $this_table_node_name;
}

1;
