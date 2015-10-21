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
        my $padding  = $self->config_get('Pad') || 0;
        $self->{'_graph'} = Bio::EnsEMBL::Hive::Utils::GraphViz->new( name => 'AnalysisWorkflow', ratio => qq{compress"; pad = "$padding}  ); # injection hack!
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


sub _analysis_node_name {
    my ($self, $analysis) = @_;

    my $analysis_node_name = 'analysis_' . $analysis->relative_display_name( $self->pipeline );
    $analysis_node_name=~s/\W/__/g;
    return $analysis_node_name;
}


sub _table_node_name {
    my ($self, $df_rule) = @_;

    my $table_node_name = 'table_' . $df_rule->to_analysis->relative_display_name( $self->pipeline ) .
                ($self->config_get('DuplicateTables') ?  '_'.$df_rule->from_analysis->logic_name : '');
    $table_node_name=~s/\W/__/g;
    return $table_node_name;
}


sub _midpoint_name {
    my ($df_rule) = @_;

    if($df_rule and scalar($df_rule)=~/\((\w+)\)/) {     # a unique id of a df_rule assuming dbIDs are not available
        return 'dfr_'.$1.'_mp';
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

    my $pipeline    = $self->pipeline;

    foreach my $source_analysis ( @{ $pipeline->get_source_analyses } ) {
            # run the recursion in each component that has a non-cyclic start:
        $self->_propagate_allocation( $source_analysis );
    }
    foreach my $cyclic_analysis ( $pipeline->collection_of( 'Analysis' )->list ) {
        next if(defined $cyclic_analysis->{'_funnel_dfr'});
        $self->_propagate_allocation( $cyclic_analysis );
    }

    if( $self->config_get('DisplayDetails') ) {
        $self->_add_pipeline_label( $pipeline->display_name );
    }

    foreach my $source_analysis ( @{ $pipeline->get_source_analyses } ) {
            # run the recursion in each component that has a non-cyclic start:
        $self->_add_analysis_node( $source_analysis );
    }
    foreach my $cyclic_analysis ( $pipeline->collection_of( 'Analysis' )->list ) {
        next if($self->{'_created_analysis'}{ $cyclic_analysis });
        $self->_add_analysis_node( $cyclic_analysis );
    }

    if($self->config_get('DisplayStretched') ) {    # put each analysis before its' funnel midpoint
        foreach my $analysis ( $pipeline->collection_of('Analysis')->list ) {
            if($analysis->{'_funnel_dfr'}) {    # this should only affect analyses that have a funnel
                my $from = $self->_analysis_node_name( $analysis );
                my $to   = _midpoint_name( $analysis->{'_funnel_dfr'} );
                $self->graph->add_edge( $from => $to,
                    color     => 'black',
                    style     => 'invis',   # toggle visibility by changing 'invis' to 'dashed'
                );
            }
        }
    }

    if($self->config_get('DisplaySemaphoreBoxes') ) {
        my %cluster_2_nodes = ();

        foreach my $analysis ( $pipeline->collection_of('Analysis')->list ) {
            if(my $funnel = $analysis->{'_funnel_dfr'}) {
                push @{$cluster_2_nodes{ _midpoint_name( $funnel ) } }, $self->_analysis_node_name( $analysis );
            }

            foreach my $df_rule ( @{ $analysis->dataflow_rules_collection } ) {
                if( $df_rule->is_a_funnel_rule and ! $df_rule->{'_funnel_dfr'} ) {

                    push @{$cluster_2_nodes{ '' }}, _midpoint_name( $df_rule );     # top-level funnels define clusters (top-level "boxes")

                } elsif( UNIVERSAL::isa($df_rule->to_analysis, 'Bio::EnsEMBL::Hive::NakedTable') ) {

                    if(my $funnel = $df_rule->to_analysis->{'_funnel_dfr'}) {
                        push @{$cluster_2_nodes{ _midpoint_name( $funnel ) } }, $self->_table_node_name( $df_rule );    # table belongs to the same "box" as the dataflow source
                    }
                }

                if(my $funnel = $df_rule->{'_funnel_dfr'}) {
                    push @{$cluster_2_nodes{ _midpoint_name( $funnel ) } }, _midpoint_name( $df_rule ); # midpoints of rules that have a funnel live inside "boxes"
                }
            }
        }

        $self->graph->cluster_2_nodes( \%cluster_2_nodes );
        $self->graph->colour_scheme( $self->config_get('Box', 'ColourScheme') );
        $self->graph->colour_offset( $self->config_get('Box', 'ColourOffset') );
    }

    return $self->graph();
}


sub _propagate_allocation {
    my ($self, $source_analysis ) = @_;

    foreach my $df_rule ( @{ $source_analysis->dataflow_rules_collection } ) {
        my $target_object       = $df_rule->to_analysis
            or die "Could not fetch a target object for url='".$df_rule->to_analysis_url."', please check your database for consistency.\n";

        my $target_node_name;

        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
            $target_node_name = $self->_analysis_node_name( $target_object );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {
            $target_node_name = $self->_table_node_name( $df_rule );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {
            next;
        } else {
            warn("Do not know how to handle the type '".ref($target_object)."'");
            next;
        }

        my $proposed_funnel_dfr;    # will depend on whether we start a new semaphore

        # --------------- first assign the rules (their midpoints if applicable) --------------------

        my $funnel_dataflow_rule;
        if( $funnel_dataflow_rule = $df_rule->funnel_dataflow_rule ) {   # if there is a new semaphore, the dfrs involved (their midpoints) will also have to be allocated
            $funnel_dataflow_rule->{'_funnel_dfr'} = $source_analysis->{'_funnel_dfr'}; # draw the funnel's midpoint outside of the box

            $proposed_funnel_dfr = $df_rule->{'_funnel_dfr'} = $funnel_dataflow_rule;       # if we do start a new semaphore, report to the new funnel (based on common funnel rule's midpoint)
        } else {
            $proposed_funnel_dfr = $source_analysis->{'_funnel_dfr'} || ''; # if we don't start a new semaphore, inherit the allocation of the source
        }

        # --------------- then assign the target_objects --------------------------------------------

            # we allocate on first-come basis at the moment:
        if( exists $target_object->{'_funnel_dfr'} ) {  # node is already allocated?

            my $known_funnel_dfr = $target_object->{'_funnel_dfr'};

            if( $known_funnel_dfr eq $proposed_funnel_dfr) {
                # warn "analysis '$target_node_name' has already been allocated to the same '$known_funnel_dfr' by another branch";
            } else {
                # warn "analysis '$target_node_name' has already been allocated to '$known_funnel_dfr' however this branch would allocate it to '$proposed_funnel_dfr'";
            }

            if($funnel_dataflow_rule) {  # correction for multiple entries into the same box (probably needs re-thinking)
                $df_rule->{'_funnel_dfr'} = $target_object->{'_funnel_dfr'};
            }

        } else {
            # warn "allocating analysis '$target_node_name' to '$proposed_funnel_dfr'";
            $target_object->{'_funnel_dfr'} = $proposed_funnel_dfr;

            if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
                $self->_propagate_allocation( $target_object );
            }
        }
    }
}


sub _add_pipeline_label {
    my ($self, $pipeline_label) = @_;

    my $node_fontname  = $self->config_get('Node', 'Details', 'Font');
    $self->graph()->add_node( 'Details',
        label     => $pipeline_label,
        fontname  => $node_fontname,
        shape     => 'plaintext',
    );
}


sub _add_analysis_node {
    my ($self, $analysis) = @_;

    my $this_analysis_node_name                           = $self->_analysis_node_name( $analysis );

    return $this_analysis_node_name if($self->{'_created_analysis'}{ $analysis }++);   # making sure every Analysis node gets created no more than once

    my $analysis_stats = $analysis->stats();

    my ($breakout_label, $total_job_count, $count_hash)   = $analysis_stats->job_count_breakout();
    my $analysis_status                                   = $analysis_stats->status;
    my $analysis_status_colour                            = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Colour');
    my $style                                             = $analysis->can_be_empty() ? 'dashed, filled' : 'filled' ;
    my $node_fontname                                     = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Font');
    my $display_stats                                     = $self->config_get('DisplayStats');
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
    my $analysis_label  = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.$colspan.'">'.$analysis->relative_display_name( $hive_pipeline ).' ('.($analysis->dbID || 'unstored').')</td></tr>';
    if( $display_stats ) {
        $analysis_label    .= qq{<tr><td colspan="$colspan"> </td></tr>};
        if( $display_stats eq 'barchart') {
            $analysis_label    .= qq{<tr>$bar_chart</tr>};
        } elsif( $display_stats eq 'text') {
            $analysis_label    .= qq{<tr><td colspan="$colspan">$breakout_label</td></tr>};
        }
    }

    if( my $job_limit = $self->config_get('DisplayJobs') ) {
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
            my $input_id = $job->input_id;
            my $status   = $job->status;
            my $job_id   = $job->dbID || 'unstored';
            $input_id=~s/\>/&gt;/g;
            $input_id=~s/\</&lt;/g;
            $input_id=~s/\{|\}//g;
            $analysis_label    .= qq{<tr><td colspan="$colspan" bgcolor="}.$self->config_get('Node', 'JobStatus', $status, 'Colour').qq{">$job_id [$status]: $input_id</td></tr>};
        }

        if($hit_limit) {
            $analysis_label    .= qq{<tr><td colspan="$colspan">[ + }.($total_job_count-$job_limit).qq{ more jobs ]</td></tr>};
        }
    }
    $analysis_label    .= '</table>>';
  
    $self->graph->add_node( $this_analysis_node_name,
        label       => $analysis_label,
        shape       => 'record',
        fontname    => $node_fontname,
        style       => $style,
        fillcolor   => $analysis_status_colour,
    );

    $self->_add_control_rules( $analysis->control_rules_collection );
    $self->_add_dataflow_rules( $analysis );

    return $this_analysis_node_name;
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


sub _branch_and_template {
    my ($self, $df_rule) = @_;

    my $input_id_template   = $self->config_get('DisplayInputIDTemplate') ? $df_rule->input_id_template : undef;
       $input_id_template   = join(",\n", sort keys( %{destringify($input_id_template)} )) if $input_id_template;

    return '#'.$df_rule->branch_code.($input_id_template ? ":\n".$input_id_template : '');
}


sub _twopart_arrow {
    my ($self, $df_rule) = @_;

    my $graph               = $self->graph();
    my $dataflow_colour     = $self->config_get('Edge', 'Data', 'Colour');
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');

    my $midpoint_name       = _midpoint_name( $df_rule );

    my $from_node_name      = $self->_analysis_node_name( $df_rule->from_analysis );
    my $target_node_name    = $self->_analysis_node_name( $df_rule->to_analysis );

    $graph->add_node( $midpoint_name,   # midpoint itself
        color       => $dataflow_colour,
        label       => '',
        shape       => 'point',
        fixedsize   => 1,
        width       => 0.01,
        height      => 0.01,
    );
    $graph->add_edge( $from_node_name => $midpoint_name, # first half of the two-part arrow
        color       => $dataflow_colour,
        arrowhead   => 'none',
        fontname    => $df_edge_fontname,
        fontcolor   => $dataflow_colour,
        label       => $self->_branch_and_template( $df_rule ),
    );
    $graph->add_edge( $midpoint_name => $target_node_name,   # second half of the two-part arrow
        color     => $dataflow_colour,
    );

    return $midpoint_name;
}


sub _add_dataflow_rules {
    my ($self, $from_analysis) = @_;

    my $graph               = $self->graph();
    my $dataflow_colour     = $self->config_get('Edge', 'Data', 'Colour');
    my $semablock_colour    = $self->config_get('Edge', 'Semablock', 'Colour');
    my $accu_colour         = $self->config_get('Edge', 'Accu', 'Colour');
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');

    foreach my $group ( @{ $from_analysis->get_grouped_dataflow_rules } ) {

        my ($df_rule, $fan_dfrs) = @$group;

        my $from_node_name  = $self->_analysis_node_name( $from_analysis );
        my $target_node_name;
        my $target_object   = $df_rule->to_analysis
            or die "Could not fetch a target object for url='".$df_rule->to_analysis_url."', please check your database for consistency.\n";

        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {

            my $funnel_analysis = $from_analysis->{'_funnel_dfr'}
                or die "Could not find funnel analysis for the ".$target_object->toString."\n";

                # one-part dashed arrow:
            $graph->add_edge( $from_node_name => _midpoint_name( $funnel_analysis ),
                color       => $accu_colour,
                style       => 'dashed',
                label       => '#'.$df_rule->branch_code.":\n".$target_object->relative_display_name( $self->pipeline ),
                fontname    => $df_edge_fontname,
                fontcolor   => $accu_colour,
                dir         => 'both',
                arrowtail   => 'crow',
            );
            next;

        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {    # skip some *really* foreign dataflow rules:

            my $from_is_local   = $df_rule->from_analysis->is_local_to( $self->pipeline );
            my $target_is_local = $target_object->is_local_to( $self->pipeline );

            if($from_is_local and !$target_is_local) {  # register a new "near neighbour" node if it's reachable by following one rule "out":
                $self->{'_foreign_analyses'}{ $target_object->relative_display_name($self->pipeline) } = $target_object;
            }

            next unless( $from_is_local or $target_is_local or $self->{'_foreign_analyses'}{ $target_object->relative_display_name($self->pipeline) } );

            $target_node_name = $self->_add_analysis_node( $target_object );

        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {

            $target_node_name = $self->_add_table_node( $df_rule );
        }

        if(@$fan_dfrs) {    # semaphored funnel case => all rules have an Analysis target and have two parts:

            my $funnel_midpoint_name = $self->_twopart_arrow( $df_rule );

            foreach my $fan_dfr (@$fan_dfrs) {

                my $fan_target_object = $fan_dfr->to_analysis;
                die "All semaphored fan rules must be wired to Analyses" unless(UNIVERSAL::isa($fan_target_object, 'Bio::EnsEMBL::Hive::Analysis'));

                $self->_add_analysis_node( $fan_target_object );

                my $fan_midpoint_name = $self->_twopart_arrow( $fan_dfr );

                    # add a semaphore inter-rule blocking arc:
                $graph->add_edge( $fan_midpoint_name => $funnel_midpoint_name,
                    color     => $semablock_colour,
                    style     => 'dashed',
                    arrowhead => 'tee',
                    dir       => 'both',
                    arrowtail => 'crow',
                );
            }

        } else {    # one-part solid arrow either to an analysis or to a table:
            $graph->add_edge( $from_node_name => $target_node_name,
                color       => $dataflow_colour,
                fontname    => $df_edge_fontname,
                fontcolor   => $dataflow_colour,
                label       => $self->_branch_and_template( $df_rule ),
            );
        }

    } # /foreach my $group
}


sub _add_table_node {
    my ($self, $df_rule) = @_;

    my $node_fontname           = $self->config_get('Node', 'Table', 'Font');
    my $hive_pipeline           = $self->pipeline;
    my $naked_table             = $df_rule->to_analysis;
    my $this_table_node_name    = $self->_table_node_name( $df_rule );

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

    if( $self->config_get('DisplayData') and $columns) {
        $table_label .= '<tr><td colspan="'.$columns.'"> </td></tr>';
        $table_label .= '<tr>'.join('', map { qq{<td bgcolor="lightblue" border="1">$_</td>} } @column_names).'</tr>';
        foreach my $row (@$table_data) {
            $table_label .= '<tr>'.join('', map { qq{<td>$_</td>} } @{$row}{@column_names}).'</tr>';
        }
        if($hit_limit) {
            $table_label  .= qq{<tr><td colspan="$columns">[ more data ]</td></tr>};
        }
    }
    $table_label .= '</table>>';

    $self->graph()->add_node( $this_table_node_name,
        label => $table_label,
        shape => 'record',
        fontname => $node_fontname,
        color => $self->config_get('Node', 'Table', 'Colour'),
    );

    return $this_table_node_name;
}

1;
