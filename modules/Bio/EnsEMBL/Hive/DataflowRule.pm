# Perl module for Bio::EnsEMBL::Hive::DataflowRule
#
# Creator: Jessica Severin <jessica@ebi.ac.uk>
# Date of creation: 22.03.2004
#
# Copyright EMBL-EBI 2000-2004
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DataflowRule

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object (methods are intelligent getters/setters) that corresponds to a row stored in 'dataflow_rule' table:

    CREATE TABLE dataflow_rule (
        dataflow_rule_id    int(10) unsigned not null auto_increment,
        from_analysis_id    int(10) unsigned NOT NULL,
        to_analysis_url     varchar(255) default '' NOT NULL,
        branch_code         int(10) default 1 NOT NULL,
        input_id_template   TEXT DEFAULT NULL,

        PRIMARY KEY (dataflow_rule_id),
        UNIQUE (from_analysis_id, to_analysis_url)
    );

    A dataflow rule is activated when a Bio::EnsEMBL::Hive::AnalysisJob::dataflow_output_id is called at any moment during a RunnableDB's execution.
    The current RunnableDB's analysis ($from_analysis) and the requested $branch_code (1 by default) define the entry conditions,
    and whatever rules match these conditions will generate new jobs with input_ids specified in the dataflow_output_id() call.
    If input_id_template happens to contain a non-NULL value, it will be used to generate the corresponding intput_id instead.

    Jessica's remark on the structure of to_analysis_url:
        Extended from design of SimpleRule concept to allow the 'to' analysis to be specified with a network savy URL like
        mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test/analysis?logic_name='blast_NCBI34'

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DataflowRule;

use strict;
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'
use Bio::EnsEMBL::Utils::Exception;
#use Bio::EnsEMBL::Hive::URLFactory;

=head2 new

  Usage   : Bio::EnsEMBL::Hive::DataflowRule->new(-from_analysis => $fromAnalysis, -to_analysis => $toAnalysis, -branch_code => $branch_code);
  Function: Constructor for DataflowRule object
  Returns : Bio::EnsEMBL::Hive::DataflowRule
  Args    : a rearrange-compatible hash
            
=cut

sub new {
    my $class = shift @_;
    my $self = bless {}, $class;

    my ( $dbID, $adaptor, $fromAnalysis, $toAnalysis, $from_analysis_id, $to_analysis_url, $branch_code, $input_id_template ) =
    rearrange( [ qw (DBID ADAPTOR FROM_ANALYSIS TO_ANALYSIS FROM_ANALYSIS_ID TO_ANALYSIS_URL BRANCH_CODE INPUT_ID_TEMPLATE) ], @_ );

        # database persistence:
    $self->dbID( $dbID )                            if(defined($dbID));
    $self->adaptor( $adaptor )                      if(defined($adaptor));

        # from objects:
    $self->from_analysis( $fromAnalysis )           if(defined($fromAnalysis));
    $self->to_analysis( $toAnalysis )               if(defined($toAnalysis));

        # simple scalars:
    $self->from_analysis_id( $from_analysis_id )    if(defined($from_analysis_id));
    $self->to_analysis_url( $to_analysis_url )      if(defined($to_analysis_url));
    $self->branch_code( $branch_code )              if(defined($branch_code));
    $self->input_id_template($input_id_template)    if(defined($input_id_template));

    return $self;
}

=head2 dbID

    Function: getter/setter method for the dbID of the dataflow rule

=cut

sub dbID {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_dbID'} = shift @_;
    }
    return $self->{'_dbID'};
}

=head2 adaptor

    Function: getter/setter method for the adaptor of the dataflow rule

=cut

sub adaptor {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_adaptor'} = shift @_;
    }
    return $self->{'_adaptor'};
}

=head2 branch_code

    Function: getter/setter method for the branch_code of the dataflow rule

=cut

sub branch_code {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_branch_code'} = shift @_;
    }
    return ($self->{'_branch_code'} ||= 1);
}

=head2 input_id_template

    Function: getter/setter method for the input_id_template of the dataflow rule

=cut

sub input_id_template {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_input_id_template'} = shift @_;
    }
    return $self->{'_input_id_template'};
}

=head2 from_analysis_id

  Arg[1]  : (optional) int $dbID
  Usage   : $self->from_analysis_id($dbID);
  Function: Get/set method for the 'from' analysis objects dbID of this rule.
  Returns : integer
  
=cut

sub from_analysis_id {
  my ($self,$analysis_id) = @_;
  if($analysis_id) {
    $self->{'_from_analysis_id'} = $analysis_id;
    $self->{'_from_analysis'} = undef;
  }
  return $self->{'_from_analysis_id'};
}


=head2 to_analysis_url

  Arg[1]  : (optional) string $url
  Usage   : $self->to_analysis_url($url);
  Function: Get/set method for the 'to' analysis objects URL for this rule
  Returns : string
  
=cut

sub to_analysis_url {
  my ($self,$url) = @_;
  if($url) {
    $self->{'_to_analysis_url'} = $url;
    $self->{'_to_analysis'} = undef;
  }
  return $self->{'_to_analysis_url'};
}


=head2 from_analysis

  Usage   : $self->from_analysis($analysis);
  Function: Get/set method for the condition analysis object of this rule.
  Returns : Bio::EnsEMBL::Analysis
  Args    : Bio::EnsEMBL::Analysis
  
=cut

sub from_analysis {
  my ($self,$analysis) = @_;

  # setter mode
  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      throw(
        "from_analysis arg must be a [Bio::EnsEMBL::Analysis]".
        "not a [$analysis]");
    }
    $self->{'_from_analysis'} = $analysis;
    $self->{'_from_analysis_id'} = $analysis->dbID;
  }
  
  # lazy load the analysis object if I can
  if(!defined($self->{'_from_analysis'})
     and defined($self->from_analysis_id)
     and defined($self->adaptor))
  {
    $self->{'_from_analysis'} =
      $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->from_analysis_id);
  }
  return $self->{'_from_analysis'};
}


=head2 to_analysis

  Usage   : $self->to_analysis($analysis);
  Function: Get/set method for the goal analysis object of this rule.
  Returns : Bio::EnsEMBL::Analysis
  Args    : Bio::EnsEMBL::Analysis
  
=cut

sub to_analysis {
  my ($self, $analysis_or_nt) = @_;

  if( defined $analysis_or_nt ) {
    unless ($analysis_or_nt->can('url')) {
      throw( "to_analysis arg must support 'url' method, '$analysis_or_nt' does not know how to do it");
    }
    $self->{'_to_analysis'} = $analysis_or_nt;

    #if the 'from' and 'to' share the same adaptor, then use a simple logic_name
    #for the URL rather than a full network distributed URL

    my $ref_rule_adaptor = $self->from_analysis->adaptor;

    if($analysis_or_nt->can('logic_name') and $self->from_analysis and ($ref_rule_adaptor == $analysis_or_nt->adaptor)) {
      $self->{'_to_analysis_url'} = $analysis_or_nt->logic_name;
    } else {
      $self->{'_to_analysis_url'} = $analysis_or_nt->url($ref_rule_adaptor->db);
    }
  }
  # lazy load the analysis object if I can
  if(!defined($self->{'_to_analysis'}) and defined($self->to_analysis_url)) {

    $self->{'_to_analysis'} = $self->adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name_or_url($self->to_analysis_url);

  }
  return $self->{'_to_analysis'};
}

sub print_rule {
  my $self = shift;
  print("DataflowRule dbID=", $self->dbID,
        "  from_id=", $self->from_analysis_id,
        "  to_url=", $self->to_analysis_url,
        "  branch=", $self->branch_code,
        "\n");
}

1;

