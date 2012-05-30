package Bio::EnsEMBL::Hive::Utils::Graph;

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

=head1 METHODS/SUBROUTINES

See inline

=head1 AUTHOR

$Author: lg4 $

=head1 VERSION

$Revision: 1.12 $

=cut

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils::GraphViz;

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::Utils::Scalar qw(check_ref assert_ref);

use Bio::EnsEMBL::Hive::Utils::Config;


=head2 new()

  Arg [DBA] : Bio::EnsEMBL::Hive::DBSQL::DBAdaptor; The adaptor to get 
              information from
  Arg [CONFIG] :  Bio::EnsEMBL::Hive::Utils::Config object used to
                  control how the object is produced.
                  If one is not given then a default instance is created
  Returntype : Graph object
  Exceptions : If the parameters are not as required
  Status     : Beta
  
=cut

sub new {
  my ($class, $dba, $config) = @_;

  my $self = bless({}, ref($class) || $class);
  $self->dba($dba);
  $self->config($config);

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
    $self->{graph} = Bio::EnsEMBL::Hive::Utils::GraphViz->new( name => 'AnalysisWorkflow', ratio => 'compress' );
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
  my ($self, $dba) = @_;
  if(defined $dba) {
    assert_ref($dba, 'Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');
    $self->{dba} = $dba;
  }
  return $self->{dba};
}


=head2 config()

  Arg [1] : The graph configuration object
  Returntype : Bio::EnsEMBL::Hive::Utils::Config.
  Exceptions : If the object given is not of the required type
  Status     : Beta

=cut

sub config {
  my ($self, $config) = @_;
  if(defined $config) {
    assert_ref($config, 'Bio::EnsEMBL::Hive::Utils::Config');
    $self->{config} = $config;
  }
  return $self->{config};
}


sub _analysis_node_name {
    my $analysis_id = shift @_;

    return 'analysis_' . $analysis_id;
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

    my $all_analyses          = $self->dba()->get_AnalysisAdaptor()->fetch_all();
    my $all_ctrl_rules        = $self->dba()->get_AnalysisCtrlRuleAdaptor()->fetch_all();
    my $all_dataflow_rules    = $self->dba()->get_DataflowRuleAdaptor()->fetch_all();

    my %inflow_count = ();    # used to detect sources (nodes with zero inflow)
    my %outflow_rules = ();   # maps from anlaysis_node_name to a list of all dataflow rules that flow out of it
    my %dfr_flows_into= ();   # maps from dfr_id to target analysis_node_name

    foreach my $rule ( @$all_dataflow_rules ) {
        if(my $to_id = $rule->to_analysis->can('dbID') && $rule->to_analysis->dbID()) {
            my $to_node_name    = _analysis_node_name( $to_id );
            $inflow_count{$to_node_name}++;
            $dfr_flows_into{$rule->dbID()} = $to_node_name;
        }
        push @{$outflow_rules{ _analysis_node_name($rule->from_analysis_id()) }}, $rule;
    }

    my %subgraph_allocation = ();

        # NB: this is a very approximate algorithm with rough edges!
        # It will not find all start nodes in cyclic components!
    foreach my $analysis_id ( map { $_->dbID } @$all_analyses ) {
        my $analysis_node_name =  _analysis_node_name( $analysis_id );
        unless($inflow_count{$analysis_node_name}) {
            _allocate_to_subgraph(\%outflow_rules, \%dfr_flows_into, $analysis_node_name, \%subgraph_allocation ); # run the recursion in each component that has a non-cyclic start
        }
    }

    $self->_add_hive_details();
    foreach my $a (@$all_analyses) {
        $self->_add_analysis_node($a);
    }
    $self->_control_rules( $all_ctrl_rules );
    $self->_dataflow_rules( $all_dataflow_rules );

    if($self->config->get('Graph', 'DisplayStretched') ) {
        while( my($from, $to) = each %subgraph_allocation) {
            if($to) {
                $self->graph->add_edge( $from => $to,
                    color     => 'black',
                    style     => 'invis',   # toggle visibility by changing 'invis' to 'dashed'
                );
            }
        }
    }

    if($self->config->get('Graph', 'DisplaySemaphoreBoxes') ) {
        $self->graph->subgraphs( \%subgraph_allocation );
    }

    return $self->graph();
}


sub _allocate_to_subgraph {
    my ( $outflow_rules, $dfr_flows_into, $parent_analysis_node_name, $subgraph_allocation ) = @_;

    my $parent_allocation = $subgraph_allocation->{ $parent_analysis_node_name };  # for some analyses it will be undef

    foreach my $rule ( @{ $outflow_rules->{$parent_analysis_node_name} } ) {
        my $to_analysis                 = $rule->to_analysis();
        next unless( $to_analysis->can('dbID'));    # skip dataflow-into-tables

        my $this_analysis_node_name     = _analysis_node_name( $rule->to_analysis->dbID() );
        my $funnel_dataflow_rule_id     = $rule->funnel_dataflow_rule_id();

        my $proposed_allocation = $funnel_dataflow_rule_id  # depends on whether we start a new semaphore
            ? $dfr_flows_into->{$funnel_dataflow_rule_id}       # if we do, report to the new funnel
            : $parent_allocation;                               # it we don't, inherit the parent's funnel

        if($funnel_dataflow_rule_id) {
            my $fan_midpoint_name = _midpoint_name( $rule->dbID() );
            $subgraph_allocation->{ $fan_midpoint_name } = $proposed_allocation;

            my $funnel_midpoint_name = _midpoint_name( $funnel_dataflow_rule_id );
            $subgraph_allocation->{ $funnel_midpoint_name } = $parent_allocation;   # draw the funnel's midpoint outside of the box
        }
        if( exists $subgraph_allocation->{ $this_analysis_node_name } ) {        # we allocate on first-come basis at the moment
            my $known_allocation = $subgraph_allocation->{ $this_analysis_node_name } || '';
            $proposed_allocation ||= '';

            if( $known_allocation eq $proposed_allocation) {
                # warn "analysis '$this_analysis_node_name' has already been allocated to the same '$known_allocation' by another branch";
            } else {
                # warn "analysis '$this_analysis_node_name' has already been allocated to '$known_allocation' however this branch would allocate it to '$proposed_allocation'";
            }

        } else {
            # warn "allocating analysis '$this_analysis_node_name' to '$proposed_allocation'";
            $subgraph_allocation->{ $this_analysis_node_name } = $proposed_allocation;

            _allocate_to_subgraph( $outflow_rules, $dfr_flows_into, $this_analysis_node_name, $subgraph_allocation );
        }
    }
}


sub _add_hive_details {
  my ($self) = @_;

  my $node_fontname  = $self->config->get('Graph', 'Fonts', 'edge');

  if($self->config->get('Graph', 'DisplayDetails') ) {
    my $dbc = $self->dba()->dbc();
    my $label = sprintf('%s@%s', $dbc->dbname, $dbc->host || '-');
    $self->graph()->add_node( 'details',
      label     => $label,
      fontname  => $node_fontname,
      shape     => 'plaintext',
    );
  }
}


sub _add_analysis_node {
  my ($self, $a) = @_;
  my $graph = $self->graph();
  
  #Check we can invoke it & then check if it was able to be empty
  my $can_be_empty = $a->stats()->can('can_be_empty') && $a->stats()->can_be_empty();
  my $shape = ($can_be_empty) ? 'doubleoctagon' : 'ellipse' ;

  my $status_colour = $self->config->get('Graph', 'Colours', 'Status', $a->stats->status)
                   || $self->config->get('Graph', 'Colours', 'Status', 'OTHER');
  my $node_fontname  = $self->config->get('Graph', 'Fonts', 'edge');
  
  $graph->add_node( _analysis_node_name( $a->dbID() ), 
    label       => $a->logic_name().' ('.$a->dbID().')\n'.$a->stats()->done_job_count().'+'.$a->stats()->remaining_job_count().'='.$a->stats()->total_job_count(), 
    shape       => $shape,
    style       => 'filled',
    fontname    => $node_fontname,
    fillcolor   => $status_colour,
  );
}


sub _control_rules {
  my ($self, $all_ctrl_rules) = @_;
  
  my $control_colour = $self->config->get('Graph', 'Colours', 'Flows', 'control');
  my $edge_fontname  = $self->config->get('Graph', 'Fonts', 'edge');
  my $graph = $self->graph();

  #The control rules are always from and to an analysis so no need to search for odd cases here
  foreach my $rule ( @$all_ctrl_rules ) {
    my ($from, $to) = ( _analysis_node_name( $rule->condition_analysis()->dbID() ), _analysis_node_name( $rule->ctrled_analysis()->dbID() ) );
    $graph->add_edge( $from => $to, 
      color => $control_colour,
      fontname => $edge_fontname,
      arrowhead => 'tee',
    );
  }
}


sub _dataflow_rules {
    my ($self, $all_dataflow_rules) = @_;

    my $graph = $self->graph();
    my $dataflow_colour  = $self->config->get('Graph', 'Colours', 'Flows', 'data');
    my $semablock_colour = $self->config->get('Graph', 'Colours', 'Flows', 'semablock');
    my $edge_fontname    = $self->config->get('Graph', 'Fonts', 'edge');

    my %needs_a_midpoint = ();
    my %aid2aid_nonsem = ();    # simply a directed graph between numerical analysis_ids, except for semaphored rules
    foreach my $rule ( @$all_dataflow_rules ) {
        if(my $to_id = $rule->to_analysis->can('dbID') && $rule->to_analysis->dbID()) {
            unless( $rule->funnel_dataflow_rule_id ) {
                $aid2aid_nonsem{$rule->from_analysis_id()}{$to_id}++;
            }
        }
        if(my $funnel_dataflow_rule_id = $rule->funnel_dataflow_rule_id()) {
            $needs_a_midpoint{$rule->dbID()}++;
            $needs_a_midpoint{$funnel_dataflow_rule_id}++;
        }
    }

    foreach my $rule ( @$all_dataflow_rules ) {
    
        my ($rule_id, $from_analysis_id, $branch_code, $funnel_dataflow_rule_id, $to) =
            ($rule->dbID(), $rule->from_analysis_id(), $rule->branch_code(), $rule->funnel_dataflow_rule_id(), $rule->to_analysis());
        my ($from_node, $to_id, $to_node) = ( _analysis_node_name($from_analysis_id)      );
    
            # Different treatment for analyses and tables:
        if(check_ref($to, 'Bio::EnsEMBL::Analysis')) {
            $to_id   = $to->dbID();
            $to_node = _analysis_node_name($to_id);
        } elsif(check_ref($to, 'Bio::EnsEMBL::Hive::NakedTable')) {
            $to_node = $to->table_name();
            $self->_add_table_node($to_node);
        } else {
            warn('Do not know how to handle the type '.ref($to));
            next;
        }

        if($needs_a_midpoint{$rule_id}) {
            my $midpoint_name = _midpoint_name($rule_id);

            $graph->add_node( $midpoint_name,   # midpoint itself
                color       => $dataflow_colour,
                label       => '',
                shape       => 'point',
                fixedsize   => 1,
                width       => 0.01,
                height      => 0.01,
            );
            $graph->add_edge( $from_node => $midpoint_name, # first half of the two-part arrow
                color       => $dataflow_colour,
                arrowhead   => 'none',
                label       => '#'.$branch_code, 
                fontname    => $edge_fontname,
            );
            $graph->add_edge( $midpoint_name => $to_node,   # second half of the two-part arrow
                color     => $dataflow_colour,
            );
            if($funnel_dataflow_rule_id) {
                $graph->add_edge( $midpoint_name => _midpoint_name($funnel_dataflow_rule_id),   # semaphore inter-rule link
                    color     => $semablock_colour,
                    fontname  => $edge_fontname,
                    style     => 'dashed',
                    arrowhead => 'tee',
                    dir       => 'both',
                    arrowtail => 'crow',
                );
            }
        } else {
                # one-part arrow:
            $graph->add_edge( $from_node => $to_node, 
                color       => $dataflow_colour,
                label       => '#'.$branch_code, 
                fontname    => $edge_fontname,
            );
        } # /if($needs_a_midpoint{$rule_id})
    } # /foreach my $rule (@$all_dataflow_rules)

}


sub _add_table_node {
  my ($self, $table) = @_;
  $self->graph()->add_node( $table, 
    label => $table.'\n', 
    fontname => 'serif',
    shape => 'tab',
    fontname => $self->config->get('Graph', 'Fonts', 'node'),
    color => $self->config->get('Graph', 'Colours', 'Status', 'TABLE'),
  );
}

1;
