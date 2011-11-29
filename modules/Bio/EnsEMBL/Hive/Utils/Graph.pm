package Bio::EnsEMBL::Hive::Utils::Graph;

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

=head1 METHODS/SUBROUTINES

See inline

=head1 AUTHOR

$Author: lg4 $

=head1 VERSION

$Revision: 1.8 $

=cut

use strict;
use warnings;
use GraphViz;

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::Utils::Scalar qw(check_ref assert_ref);

use Bio::EnsEMBL::Hive::Utils::Graph::Config;

=pod

=head2 new()

  Arg [DBA] : Bio::EnsEMBL::Hive::DBSQL::DBAdaptor; The adaptor to get 
              information from
  Arg [CONFIG] :  Bio::EnsEMBL::Hive::Utils::Graph::Config object used to
                  control how the object is produced. If one is not given
                  then a default instance is created
  Returntype : Graph object
  Exceptions : If the parameters are not as required
  Status     : Beta
  
=cut

sub new {
  my ($class, @args) = @_;
  my $self = bless({}, ref($class) || $class);
  my ($dba, $config) = rearrange([qw(dba config)], @args);
  $self->dba($dba);
  $self->config($config);
  return $self;
}

=pod

=head2 graph()

  Arg [1] : The GraphViz instance created by this module
  Returntype : GraphViz
  Exceptions : None
  Status     : Beta

=cut

sub graph {
  my ($self) = @_;
  if(! exists $self->{graph}) {
    $self->{graph} = GraphViz->new( name => 'AnalysisWorkflow', ratio => 'compress' );
  }
  return $self->{graph};
}

=pod

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

=pod

=head2 config()

  Arg [1] : The graph configuration object
  Returntype : Graph::Config.
  Exceptions : If the object given is not of the required type
  Status     : Beta

=cut

sub config {
  my ($self, $config) = @_;
  if(defined $config) {
    assert_ref($config, 'Bio::EnsEMBL::Hive::Utils::Graph::Config');
    $self->{config} = $config;
  }
  if(! exists $self->{config}) {
    $self->{config} = Bio::EnsEMBL::Hive::Utils::Graph::Config->new();
  }
  return $self->{config};
}

=pod

=head2 build()

  Returntype : The GraphViz object built & populated
  Exceptions : Raised if there are issues with accessing the database
  Description : Builds the graph object and returns it.
  Status     : Beta

=cut

sub build {
  my ($self) = @_;
  $self->_add_hive_details();
  my $analyses = $self->dba()->get_AnalysisAdaptor()->fetch_all();
  foreach my $a (@{$analyses}) {
    $self->_add_analysis_node($a);
  }
  $self->_control_rules();
  $self->_dataflow_rules();
  return $self->graph();
}

sub _add_hive_details {
  my ($self) = @_;
  if($self->config()->{DisplayDetails}) {
    my $dbc = $self->dba()->dbc();
    my $label = sprintf('%s@%s', $dbc->dbname, $dbc->host || '-');
    $self->graph()->add_node(
      'details',
      label => $label,
      fontname => $self->config()->{Fonts}->{node},
      shape => 'plaintext' 
    );
  }
}


sub _add_analysis_node {
  my ($self, $a) = @_;
  my $graph = $self->graph();
  
  #Check we can invoke it & then check if it was able to be empty
  my $can_be_empty = $a->stats()->can('can_be_empty') && $a->stats()->can_be_empty();
  my $shape = ($can_be_empty) ? 'doubleoctagon' : 'ellipse' ;

  my $config = $self->config()->{Colours}->{Status};
  my $colour = $config->{$a->stats()->status()} || $config->{OTHER};
  
  $graph->add_node(
    $a->dbID(), 
    label       => $a->logic_name().' ('.$a->dbID().')\n'.$a->stats()->done_job_count().'+'.$a->stats()->remaining_job_count().'='.$a->stats()->total_job_count(), 
    shape       => $shape,
    style       => 'filled',
    fontname    => $self->config()->{Fonts}->{node},
    fillcolor   => $colour,
  );
}


sub _control_rules {
  my ($self) = @_;
  
  my $config = $self->config()->{Colours}->{Flows};
  my $graph = $self->graph();
  my $ctrl_rules = $self->dba()->get_AnalysisCtrlRuleAdaptor()->fetch_all();

  #The control rules are always from and to an analysis so no need to search for odd cases here
  foreach my $rule (@{$ctrl_rules}) {
    my ($from, $to) = ($rule->condition_analysis()->dbID(), $rule->ctrled_analysis()->dbID());
    $graph->add_edge($from => $to, 
      color => $config->{control},
      fontname => $self->config()->{Fonts}->{edge},
      arrowhead => 'tee',
    );
  }
}

sub _midpoint_name {
    my $rule_id = shift @_;

    return 'dfr_'.$rule_id.'_mp';
}

sub _dataflow_rules {
  my ($self) = @_;
  my $graph = $self->graph();
  my $config = $self->config()->{Colours}->{Flows};
  my $dataflow_rules = $self->dba()->get_DataflowRuleAdaptor()->fetch_all();

  foreach my $rule (@{$dataflow_rules}) {
    
    my ($from_analysis_id, $branch_code, $funnel_dataflow_rule_id, $to) = ($rule->from_analysis_id(), $rule->branch_code(), $rule->funnel_dataflow_rule_id(), $rule->to_analysis());
    my $to_node;
    
    #If we've been told to flow from an analysis to a table or external source we need
    #to process this differently
    if(check_ref($to, 'Bio::EnsEMBL::Analysis')) {
      $to_node = $to->dbID();
    } elsif(check_ref($to, 'Bio::EnsEMBL::Hive::NakedTable')) {
        $to_node = $to->table_name();
        $self->_add_table_node($to_node);
    } else {
        warn('Do not know how to handle the type '.ref($to));
        next;
    }
    
      my $midpoint_name = _midpoint_name($rule->dbID);

      $graph->add_edge($from_analysis_id => $midpoint_name, 
        color       => $config->{data}, 
        arrowhead   => 'none',
        label       => '#'.$branch_code, 
        fontname    => $self->config()->{Fonts}->{edge},
      );
      $graph->add_node(
        $midpoint_name,
        label       => '',
        defined($funnel_dataflow_rule_id)
            ? (
                shape   => 'circle',
                fixedsize   => 1,
                width       => 0.1,
                height      => 0.1,
            ) : (
                shape   => 'point',
                fixedsize   => 1,
                width       => 0.01,
                height      => 0.01,
            ),
        color       => $config->{data}, 
      );
      $graph->add_edge($midpoint_name => $to_node, 
          color     => $config->{data}, 
      );
      if($funnel_dataflow_rule_id) {
          $graph->add_edge( $midpoint_name => _midpoint_name($funnel_dataflow_rule_id), 
              color     => $config->{semablock},
              fontname  => $self->config()->{Fonts}->{edge},
              style     => 'dashed',
              arrowhead => 'tee',
          );
      }
  }
}

sub _add_table_node {
  my ($self, $table) = @_;
  $self->graph()->add_node(
    $table, 
    label => $table.'\n', 
    fontname => 'serif',
    shape => 'tab',
    fontname => $self->config()->{Fonts}->{node},
    color => $self->config()->{Colours}->{Status}->{TABLE}
  );
}

1;
