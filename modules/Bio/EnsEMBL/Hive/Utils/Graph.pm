=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Graph

=head1 SYNOPSIS

    my $dba = get_hive_dba();
    my $g = Bio::EnsEMBL::Hive::Utils::Graph->new(-DBA => $dba);
    my $graphviz = $g->build();
    $graphviz->as_png('location.png');

=head1 DESCRIPTION

    This is a module for converting a hive database's flow of analyses, control 
    rules and dataflows into the GraphViz model language. This information can
    then be converted to an image or to the dot language for further manipulation
    in GraphViz.

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Utils::Graph;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils::GraphViz;
use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::Utils::Config;

use base ('Bio::EnsEMBL::Hive::Configurable');


=head2 new()

  Arg [1] : Bio::EnsEMBL::Hive::DBSQL::DBAdaptor $dba;
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
  my ($class, $dba, $config_file_name) = @_;

  my $self = bless({}, ref($class) || $class);

  $self->dba($dba);
  my $config = Bio::EnsEMBL::Hive::Utils::Config->new( $config_file_name ? $config_file_name : () );
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

    if(! exists $self->{graph}) {
        my $padding  = $self->config_get('Pad') || 0;
        $self->{graph} = Bio::EnsEMBL::Hive::Utils::GraphViz->new( name => 'AnalysisWorkflow', ratio => qq{compress"; pad = "$padding}  ); # injection hack!
    }
    return $self->{graph};
}


=head2 dba()

  Arg [1] : The DBAdaptor instance
  Returntype : DBAdaptor
  Exceptions : If the given object is not a hive DBAdaptor
  Status     : Beta

=cut

sub dba {
    my $self = shift @_;

    if(@_) {
        $self->{dba} = shift @_;
    }

    return $self->{dba};
}


sub _analysis_node_name {
    my $analysis = shift @_;

#    return 'analysis_' . $analysis->dbID;
    return 'analysis_' . $analysis->logic_name;
}

sub _table_node_name {
    my ($self, $df_rule) = @_;

    return 'table_' . $df_rule->to_analysis->table_name .
                ($self->config_get('DuplicateTables') ?  '_'.$df_rule->from_analysis->logic_name : '');
}


sub _midpoint_name {
    my $rule_id = shift @_;

    return 'dfr_'.$rule_id.'_mp';
}


=head2 build()

  Returntype : The GraphViz object built & populated
  Exceptions : Raised if there are issues with accessing the database
  Description : Builds the graph object and returns it.
  Status     : Beta

=cut

sub build {
    my ($self) = @_;

    my $all_analyses_coll       = Bio::EnsEMBL::Hive::Utils::Collection->new( $self->dba()->get_AnalysisAdaptor()->fetch_all );
    my $all_control_rules_coll  = Bio::EnsEMBL::Hive::Utils::Collection->new( $self->dba()->get_AnalysisCtrlRuleAdaptor()->fetch_all );
    my $all_dataflow_rules_coll = Bio::EnsEMBL::Hive::Utils::Collection->new( $self->dba()->get_DataflowRuleAdaptor()->fetch_all );

    foreach my $c_rule ( $all_control_rules_coll->list ) {
        my $ctrled_analysis = $all_analyses_coll->find_one_by('dbID', $c_rule->ctrled_analysis_id );
        $c_rule->ctrled_analysis( $ctrled_analysis );
        push @{$ctrled_analysis->control_rules_collection}, $c_rule;
    }

    foreach my $df_rule ( $all_dataflow_rules_coll->list ) {
        my $from_analysis = $all_analyses_coll->find_one_by('dbID', $df_rule->from_analysis_id );
        $df_rule->from_analysis( $from_analysis );
        push @{$from_analysis->dataflow_rules_collection}, $df_rule;

        if(my $target_object = $all_analyses_coll->find_one_by('logic_name', $df_rule->to_analysis_url )) {
            $df_rule->to_analysis( $target_object );
            if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
                $target_object->{'_inflow_count'}++;
            }
        } # otherwise it may be a link out (unsupported at the moment)
    }

    my %subgraph_allocation = ();   # maps node names to midpoint names of the funnel dataflow rule (or null if toplevel)

        # NB: this is a very approximate algorithm with rough edges!
        # It will not find all start nodes in cyclic components!
    foreach my $source_analysis ( $all_analyses_coll->list ) {
        unless( $source_analysis->{'_inflow_count'} ) {    # if there is no dataflow into this analysis
                # run the recursion in each component that has a non-cyclic start:
            $self->_allocate_to_subgraph( $source_analysis, \%subgraph_allocation );
        }
    }

    $self->_add_hive_details();
    foreach my $analysis ( $all_analyses_coll->list ) {
        $self->_add_analysis_node($analysis);
    }
    foreach my $analysis ( $all_analyses_coll->list ) {
        $self->_control_rules( $analysis->control_rules_collection );
        $self->_dataflow_rules( $analysis->dataflow_rules_collection, \%subgraph_allocation );
    }

    if($self->config_get('DisplayStretched') ) {
        while( my($from, $to) = each %subgraph_allocation) {
            if($to && $from=~/^analysis/) {
                $self->graph->add_edge( $from => $to,
                    color     => 'black',
                    style     => 'invis',   # toggle visibility by changing 'invis' to 'dashed'
                );
            }
        }
    }

    if($self->config_get('DisplaySemaphoreBoxes') ) {
        $self->graph->subgraphs( \%subgraph_allocation );
        $self->graph->colour_scheme( $self->config_get('Box', 'ColourScheme') );
        $self->graph->colour_offset( $self->config_get('Box', 'ColourOffset') );
    }

    return $self->graph();
}


sub _allocate_to_subgraph {
    my ($self, $source_analysis, $subgraph_allocation ) = @_;

    my $source_analysis_allocation  = $subgraph_allocation->{ _analysis_node_name( $source_analysis ) };  # for some analyses it will be undef

    foreach my $df_rule ( @{ $source_analysis->dataflow_rules_collection } ) {    # this will only work if the analyses objects are ALL cached before loading DFRs
        my $target_object       = $df_rule->to_analysis();
        my $target_node_name;

        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
            $target_node_name = _analysis_node_name( $target_object );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {
            $target_node_name = $self->_table_node_name( $df_rule );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {
            next;
        } else {
            warn('Do not know how to handle the type '.ref($target_object));
            next;
        }

        my $proposed_allocation;    # will depend on whether we start a new semaphore
        my $funnel_dataflow_rule_id  = $df_rule->funnel_dataflow_rule_id();
        if( $funnel_dataflow_rule_id ) {
            $proposed_allocation =
                _midpoint_name( $funnel_dataflow_rule_id );       # if we do start a new semaphore, report to the new funnel (based on common funnel rule's midpoint)

            my $fan_midpoint_name = _midpoint_name( $df_rule->dbID );
            $subgraph_allocation->{ $fan_midpoint_name } = $proposed_allocation;

            my $funnel_midpoint_name = _midpoint_name( $funnel_dataflow_rule_id );
            $subgraph_allocation->{ $funnel_midpoint_name } = $source_analysis_allocation;   # draw the funnel's midpoint outside of the box
        } else {
            $proposed_allocation = $source_analysis_allocation;   # if we don't start a new semaphore, inherit the allocation of the source
        }

            # we allocate on first-come basis at the moment:
        if( exists $subgraph_allocation->{ $target_node_name } ) {  # already allocated?
            my $known_allocation = $subgraph_allocation->{ $target_node_name } || '';
            $proposed_allocation ||= '';

            if( $known_allocation eq $proposed_allocation) {
                # warn "analysis '$target_node_name' has already been allocated to the same '$known_allocation' by another branch";
            } else {
                # warn "analysis '$target_node_name' has already been allocated to '$known_allocation' however this branch would allocate it to '$proposed_allocation'";
            }

            if($funnel_dataflow_rule_id) {  # correction for multiple entries into the same box (probably needs re-thinking)
                my $fan_midpoint_name = _midpoint_name( $df_rule->dbID );
                $subgraph_allocation->{ $fan_midpoint_name } = $subgraph_allocation->{ $target_node_name };
            }

        } else {
            # warn "allocating analysis '$target_node_name' to '$proposed_allocation'";
            $subgraph_allocation->{ $target_node_name } = $proposed_allocation;

            if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
                $self->_allocate_to_subgraph( $target_object, $subgraph_allocation );
            }
        }
    }
}


sub _add_hive_details {
  my ($self) = @_;

  my $node_fontname  = $self->config_get('Node', 'Details', 'Font');

  if( $self->config_get('DisplayDetails') ) {
    my $dbc = $self->dba()->dbc();
    my $label = sprintf('%s@%s', $dbc->dbname, $dbc->host || '-');
    $self->graph()->add_node( 'Details',
      label     => $label,
      fontname  => $node_fontname,
      shape     => 'plaintext',
    );
  }
}


sub _add_analysis_node {
    my ($self, $analysis) = @_;

    my $analysis_stats = $analysis->stats();

    my ($breakout_label, $total_job_count, $count_hash)   = $analysis_stats->job_count_breakout();
    my $analysis_status                                   = $analysis_stats->status;
    my $analysis_status_colour                            = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Colour');
    my $style                                             = $analysis->can_be_empty() ? 'dashed, filled' : 'filled' ;
    my $node_fontname                                     = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Font');
    my $display_stats                                     = $self->config_get('DisplayStats');

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
    my $analysis_label  = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.$colspan.'">'.$analysis->logic_name().' ('.$analysis->dbID.')</td></tr>';
    if( $display_stats ) {
        $analysis_label    .= qq{<tr><td colspan="$colspan"> </td></tr>};
        if( $display_stats eq 'barchart') {
            $analysis_label    .= qq{<tr>$bar_chart</tr>};
        } elsif( $display_stats eq 'text') {
            $analysis_label    .= qq{<tr><td colspan="$colspan">$breakout_label</td></tr>};
        }
    }

    if( my $job_limit = $self->config_get('DisplayJobs') ) {
        my $adaptor = $self->dba->get_AnalysisJobAdaptor();
        my @jobs = sort {$a->dbID <=> $b->dbID} @{ $adaptor->fetch_some_by_analysis_id_limit( $analysis->dbID, $job_limit+1 )};

        my $hit_limit;
        if(scalar(@jobs)>$job_limit) {
            pop @jobs;
            $hit_limit = 1;
        }

        $analysis_label    .= '<tr><td colspan="'.$colspan.'"> </td></tr>';
        foreach my $job (@jobs) {
            my $input_id = $job->input_id;
            my $status   = $job->status;
            my $job_id   = $job->dbID;
            $input_id=~s/\>/&gt;/g;
            $input_id=~s/\</&lt;/g;
            $input_id=~s/\{|\}//g;
            $analysis_label    .= qq{<tr><td colspan="$colspan" bgcolor="}.$self->config_get('Node', 'JobStatus', $status, 'Colour').qq{">$job_id [$status]: $input_id</td></tr>};
        }

        if($hit_limit) {
            $analysis_label    .= qq{<tr><td colspan="$colspan">[ and }.($total_job_count-$job_limit).qq{ more ]</td></tr>};
        }
    }
    $analysis_label    .= '</table>>';
  
    $self->graph->add_node( _analysis_node_name( $analysis ),
        label       => $analysis_label,
        shape       => 'record',
        fontname    => $node_fontname,
        style       => $style,
        fillcolor   => $analysis_status_colour,
    );
}


sub _control_rules {
  my ($self, $ctrl_rules) = @_;
  
  my $control_colour = $self->config_get('Edge', 'Control', 'Colour');
  my $graph = $self->graph();

      #The control rules are always from and to an analysis so no need to search for odd cases here
  foreach my $c_rule ( @$ctrl_rules ) {
    my $from_node_name = _analysis_node_name( $c_rule->condition_analysis );
    my $to_node_name   = _analysis_node_name( $c_rule->ctrled_analysis );

    $graph->add_edge( $from_node_name => $to_node_name,
      color => $control_colour,
      arrowhead => 'tee',
    );
  }
}


sub _dataflow_rules {
    my ($self, $dataflow_rules, $subgraph_allocation) = @_;

    my $graph = $self->graph();
    my $dataflow_colour     = $self->config_get('Edge', 'Data', 'Colour');
    my $semablock_colour    = $self->config_get('Edge', 'Semablock', 'Colour');
    my $accu_colour         = $self->config_get('Edge', 'Accu', 'Colour');
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');

    my %needs_a_midpoint = ();
    foreach my $df_rule ( @$dataflow_rules ) {
        if( my $funnel_dataflow_rule_id = $df_rule->funnel_dataflow_rule_id ) {
            $needs_a_midpoint{ $df_rule->dbID }++;
            $needs_a_midpoint{ $funnel_dataflow_rule_id }++;
        }
    }

    foreach my $df_rule ( @$dataflow_rules ) {
    
        my ($rule_id, $from_analysis, $branch_code, $funnel_dataflow_rule_id, $target_object) =
            ($df_rule->dbID, $df_rule->from_analysis, $df_rule->branch_code, $df_rule->funnel_dataflow_rule_id, $df_rule->to_analysis);
        my $from_node_name = _analysis_node_name( $from_analysis );
        my $target_node_name;
    
            # Different treatment for analyses and tables:
        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
            $target_node_name = _analysis_node_name( $target_object );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {

            $target_node_name = $self->_table_node_name( $df_rule );

            $self->_add_table_node($target_node_name, $target_object->table_name);
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {
            $target_node_name = $subgraph_allocation->{$from_node_name};

        } else {
            warn('Do not know how to handle the type '.ref($target_object));
            next;
        }

        if($needs_a_midpoint{$rule_id}) {
            my $midpoint_name = _midpoint_name( $rule_id );

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
                label       => '#'.$branch_code,
            );
            $graph->add_edge( $midpoint_name => $target_node_name,   # second half of the two-part arrow
                color     => $dataflow_colour,
            );
            if($funnel_dataflow_rule_id) {
                $graph->add_edge( $midpoint_name => _midpoint_name( $funnel_dataflow_rule_id ),   # semaphore inter-rule link
                    color     => $semablock_colour,
                    style     => 'dashed',
                    arrowhead => 'tee',
                    dir       => 'both',
                    arrowtail => 'crow',
                );
            }
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {
                # one-part dashed arrow:
            $graph->add_edge( $from_node_name => $target_node_name,
                color       => $accu_colour,
                style       => 'dashed',
                label       => $target_object->struct_name().'#'.$branch_code,
                fontname    => $df_edge_fontname,
                fontcolor   => $accu_colour,
                dir         => 'both',
                arrowtail   => 'crow',
            );
        } else {
                # one-part solid arrow:
            $graph->add_edge( $from_node_name => $target_node_name,
                color       => $dataflow_colour,
                fontname    => $df_edge_fontname,
                fontcolor   => $dataflow_colour,
                label       => '#'.$branch_code,
            );
        } # /if($needs_a_midpoint{$rule_id})
    } # /foreach my $df_rule (@$dataflow_rules)

}


sub _add_table_node {
    my ($self, $table_node_name, $table_name) = @_;

    my $node_fontname    = $self->config_get('Node', 'Table', 'Font');
    my (@column_names, $columns, $table_data, $data_limit, $hit_limit);

    if( $data_limit = $self->config_get('DisplayData') ) {
        my $adaptor = $self->dba->get_NakedTableAdaptor();
        $adaptor->table_name( $table_name );

        @column_names = sort keys %{$adaptor->column_set};
        $columns = scalar(@column_names);
        $table_data = $adaptor->fetch_all( 'LIMIT '.($data_limit+1) );

        if(scalar(@$table_data)>$data_limit) {
            pop @$table_data;
            $hit_limit = 1;
        }
    }

    my $table_label = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.($columns||1).'">'.$table_name.'</td></tr>';

    if( $self->config_get('DisplayData') ) {
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

    $self->graph()->add_node( $table_node_name, 
        label => $table_label,
        shape => 'record',
        fontname => $node_fontname,
        color => $self->config_get('Node', 'Table', 'Colour'),
    );
}

1;
