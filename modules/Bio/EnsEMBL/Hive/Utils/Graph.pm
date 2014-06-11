=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Graph

=head1 SYNOPSIS

    my $hive_dba = get_hive_dba();
    my $g = Bio::EnsEMBL::Hive::Utils::Graph->new(-DBA => $hive_dba);
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
use Bio::EnsEMBL::Hive::Analysis;
use Bio::EnsEMBL::Hive::AnalysisStats;
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;
use Bio::EnsEMBL::Hive::DataflowRule;

use base ('Bio::EnsEMBL::Hive::Configurable');


=head2 new()

  Arg [1] : Bio::EnsEMBL::Hive::DBSQL::DBAdaptor $hive_dba;
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
  my ($class, $hive_dba, $config_file_name) = @_;

  my $self = bless({}, ref($class) || $class);

  $self->hive_dba($hive_dba);
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


=head2 hive_dba()

  Arg [1] : The DBAdaptor instance
  Returntype : DBAdaptor
  Exceptions : If the given object is not a hive DBAdaptor
  Status     : Beta

=cut

sub hive_dba {
    my $self = shift @_;

    if(@_) {
        $self->{'hive_dba'} = shift @_;
    }

    return $self->{'hive_dba'};
}


sub _analysis_node_name {
    my ($self, $analysis) = @_;

    my $analysis_node_name = 'analysis_' . $analysis->display_name( $self->hive_dba );
    $analysis_node_name=~s/\W/__/g;
    return $analysis_node_name;
}


sub _table_node_name {
    my ($self, $df_rule) = @_;

    my $table_node_name = 'table_' . $df_rule->to_analysis->display_name( $self->hive_dba ) .
                ($self->config_get('DuplicateTables') ?  '_'.$df_rule->from_analysis->logic_name : '');
    $table_node_name=~s/\W/__/g;
    return $table_node_name;
}


sub _midpoint_name {
    my ($df_rule) = @_;

    if(scalar($df_rule)=~/\((\w+)\)/) {     # a unique id of a df_rule assuming dbIDs are not available
        return 'dfr_'.$1.'_mp';
    } else {
        die "Wrong argument to _midpoint_name";
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

    my $hive_dba = $self->hive_dba;

    if( my $job_limit = $self->config_get('DisplayJobs') and my $job_adaptor = $hive_dba && $hive_dba->get_AnalysisJobAdaptor ) {
        foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
            my @jobs = sort {$a->dbID <=> $b->dbID} @{ $job_adaptor->fetch_some_by_analysis_id_limit( $analysis->dbID, $job_limit+1 )};
            $analysis->jobs_collection( \@jobs );
        }
    }

    foreach my $df_rule ( Bio::EnsEMBL::Hive::DataflowRule->collection()->list ) {

        if(my $target_object = Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $df_rule->to_analysis_url )) {
            $df_rule->to_analysis( $target_object );
            if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
                $target_object->{'_inflow_count'}++;
            }
        } elsif( $df_rule->to_analysis->isa('Bio::EnsEMBL::Hive::Analysis') ) { # dataflow target is a foreign Analysis
            $target_object = $df_rule->to_analysis();
            $target_object->{'_foreign'}=1;
            Bio::EnsEMBL::Hive::Analysis->collection()->add( $target_object );  # add it to the collection
        }

        if( my $funnel_dataflow_rule  = $df_rule->funnel_dataflow_rule ) {
            $funnel_dataflow_rule->{'_is_a_funnel'}++;
        }
    }

    foreach my $c_rule ( Bio::EnsEMBL::Hive::AnalysisCtrlRule->collection()->list ) {   # control rule's condition is a foreign Analysis
        unless( Bio::EnsEMBL::Hive::Analysis->collection()->find_one_by('logic_name', $c_rule->condition_analysis_url )) {
            my $condition_analysis = $c_rule->condition_analysis();
            $condition_analysis->{'_foreign'}=1;
            Bio::EnsEMBL::Hive::Analysis->collection()->add( $condition_analysis ); # add it to the collection
        }
    }

        # NB: this is a very approximate algorithm with rough edges!
        # It will not find all start nodes in cyclic components!
    foreach my $source_analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
        unless( $source_analysis->{'_inflow_count'} or $source_analysis->{'_foreign'} ) {    # if there is no dataflow into this analysis
                # run the recursion in each component that has a non-cyclic start:
            $self->_propagate_allocation( $source_analysis );
        }
    }

    if( $self->config_get('DisplayDetails') and my $dbc = $hive_dba && $hive_dba->dbc ) {
        my $pipeline_label = sprintf('%s@%s', $dbc->dbname, $dbc->host || '-');
        $self->_add_pipeline_label( $pipeline_label );
    }
    foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
        $self->_add_analysis_node($analysis);
    }
    foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
        $self->_add_control_rules( $analysis->control_rules_collection );
        $self->_add_dataflow_rules( $analysis->dataflow_rules_collection );
    }

    if($self->config_get('DisplayStretched') ) {    # put each analysis before its' funnel midpoint
        foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
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

        foreach my $analysis ( Bio::EnsEMBL::Hive::Analysis->collection()->list ) {
            if(my $funnel = $analysis->{'_funnel_dfr'}) {
                push @{$cluster_2_nodes{ _midpoint_name( $funnel ) } }, $self->_analysis_node_name( $analysis );
            }

            foreach my $df_rule ( @{ $analysis->dataflow_rules_collection } ) {
                if( $df_rule->{'_is_a_funnel'} and ! $df_rule->{'_funnel_dfr'} ) {

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

    foreach my $df_rule ( @{ $source_analysis->dataflow_rules_collection } ) {    # this will only work if the analyses objects are ALL cached before loading DFRs
        my $target_object       = $df_rule->to_analysis();
        my $target_node_name;

        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {
            $target_node_name = $self->_analysis_node_name( $target_object );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {
            $target_node_name = $self->_table_node_name( $df_rule );
        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {
            next;
        } else {
            warn('Do not know how to handle the type '.ref($target_object));
            next;
        }

        my $proposed_funnel_dfr;    # will depend on whether we start a new semaphore

        my $funnel_dataflow_rule  = $df_rule->funnel_dataflow_rule();
        if( $funnel_dataflow_rule ) {   # if there is a new semaphore, the dfrs involved (their midpoints) will also have to be allocated
            $proposed_funnel_dfr = $funnel_dataflow_rule;       # if we do start a new semaphore, report to the new funnel (based on common funnel rule's midpoint)

            $df_rule->{'_funnel_dfr'} = $proposed_funnel_dfr;

            $funnel_dataflow_rule->{'_funnel_dfr'} = $source_analysis->{'_funnel_dfr'}; # draw the funnel's midpoint outside of the box
        } else {
            $proposed_funnel_dfr = $source_analysis->{'_funnel_dfr'} || ''; # if we don't start a new semaphore, inherit the allocation of the source
        }

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

    my $analysis_stats = $analysis->stats();

    my ($breakout_label, $total_job_count, $count_hash)   = $analysis_stats->job_count_breakout();
    my $analysis_status                                   = $analysis_stats->status;
    my $analysis_status_colour                            = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Colour');
    my $style                                             = $analysis->can_be_empty() ? 'dashed, filled' : 'filled' ;
    my $node_fontname                                     = $self->config_get('Node', 'AnalysisStatus', $analysis_status, 'Font');
    my $display_stats                                     = $self->config_get('DisplayStats');
    my $hive_dba                                          = $self->hive_dba;

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
    my $analysis_label  = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.$colspan.'">'.$analysis->display_name( $hive_dba ).' ('.($analysis->dbID || '?').')</td></tr>';
    if( $display_stats ) {
        $analysis_label    .= qq{<tr><td colspan="$colspan"> </td></tr>};
        if( $display_stats eq 'barchart') {
            $analysis_label    .= qq{<tr>$bar_chart</tr>};
        } elsif( $display_stats eq 'text') {
            $analysis_label    .= qq{<tr><td colspan="$colspan">$breakout_label</td></tr>};
        }
    }

    if( my $job_limit = $self->config_get('DisplayJobs') ) {
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
  
    $self->graph->add_node( $self->_analysis_node_name( $analysis ),
        label       => $analysis_label,
        shape       => 'record',
        fontname    => $node_fontname,
        style       => $style,
        fillcolor   => $analysis_status_colour,
    );
}


sub _add_control_rules {
  my ($self, $ctrl_rules) = @_;
  
  my $control_colour = $self->config_get('Edge', 'Control', 'Colour');
  my $graph = $self->graph();

      #The control rules are always from and to an analysis so no need to search for odd cases here
  foreach my $c_rule ( @$ctrl_rules ) {
    my $from_node_name = $self->_analysis_node_name( $c_rule->condition_analysis );
    my $to_node_name   = $self->_analysis_node_name( $c_rule->ctrled_analysis );

    $graph->add_edge( $from_node_name => $to_node_name,
      color => $control_colour,
      arrowhead => 'tee',
    );
  }
}


sub _add_dataflow_rules {
    my ($self, $dataflow_rules) = @_;

    my $graph = $self->graph();
    my $dataflow_colour     = $self->config_get('Edge', 'Data', 'Colour');
    my $semablock_colour    = $self->config_get('Edge', 'Semablock', 'Colour');
    my $accu_colour         = $self->config_get('Edge', 'Accu', 'Colour');
    my $df_edge_fontname    = $self->config_get('Edge', 'Data', 'Font');

    foreach my $df_rule ( @$dataflow_rules ) {
    
        my ($from_analysis, $branch_code, $funnel_dataflow_rule, $target_object) =
            ($df_rule->from_analysis, $df_rule->branch_code, $df_rule->funnel_dataflow_rule, $df_rule->to_analysis);
        my $from_node_name = $self->_analysis_node_name( $from_analysis );
        my $target_node_name;
    
            # Different treatment for analyses and tables:
        if(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Analysis')) {

            $target_node_name = $self->_analysis_node_name( $target_object );

        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::NakedTable')) {

            $target_node_name = $self->_table_node_name( $df_rule );
            $self->_add_table_node($target_node_name, $target_object);

        } elsif(UNIVERSAL::isa($target_object, 'Bio::EnsEMBL::Hive::Accumulator')) {

            $target_node_name = _midpoint_name( $from_analysis->{'_funnel_dfr'} );

        } else {
            warn('Do not know how to handle the type '.ref($target_object));
            next;
        }

            # a rule needs a midpoint either if it HAS a funnel or if it IS a funnel
        if( $funnel_dataflow_rule or $df_rule->{'_is_a_funnel'} ) {
            my $midpoint_name = _midpoint_name( $df_rule );

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
            if($funnel_dataflow_rule) {
                $graph->add_edge( $midpoint_name => _midpoint_name( $funnel_dataflow_rule ),   # semaphore inter-rule link
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
        } # /if( "$df_rule needs a midpoint" )
    } # /foreach my $df_rule (@$dataflow_rules)

}


sub _add_table_node {
    my ($self, $table_node_name, $naked_table) = @_;

    my $node_fontname    = $self->config_get('Node', 'Table', 'Font');
    my (@column_names, $columns, $table_data, $data_limit, $hit_limit);

    my $hive_dba = $self->hive_dba;

    if( $data_limit = $self->config_get('DisplayData') and my $naked_table_adaptor = $hive_dba && $hive_dba->get_NakedTableAdaptor ) {
        $naked_table_adaptor->table_name( $naked_table->table_name );

        @column_names = sort keys %{$naked_table_adaptor->column_set};
        $columns = scalar(@column_names);
        $table_data = $naked_table_adaptor->fetch_all( 'LIMIT '.($data_limit+1) );

        if(scalar(@$table_data)>$data_limit) {
            pop @$table_data;
            $hit_limit = 1;
        }
    }

    my $table_label = '<<table border="0" cellborder="0" cellspacing="0" cellpadding="1"><tr><td colspan="'.($columns||1).'">'. $naked_table->display_name( $hive_dba ) .'</td></tr>';

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
