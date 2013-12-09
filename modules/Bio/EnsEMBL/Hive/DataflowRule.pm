=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DataflowRule

=head1 DESCRIPTION

    A data container object (methods are intelligent getters/setters) that corresponds to a row stored in 'dataflow_rule' table:

    CREATE TABLE dataflow_rule (
        dataflow_rule_id    int(10) unsigned NOT NULL AUTO_INCREMENT,
        from_analysis_id    int(10) unsigned NOT NULL,
        branch_code         int(10) default 1 NOT NULL,
        funnel_dataflow_rule_id  int(10) unsigned default NULL,
        to_analysis_url     varchar(255) default '' NOT NULL,
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

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DataflowRule;

use strict;

use Bio::EnsEMBL::Utils::Argument ('rearrange');
use Bio::EnsEMBL::Utils::Exception ('throw');

use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor;

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );


=head2 new

  Usage   : Bio::EnsEMBL::Hive::DataflowRule->new(-from_analysis => $fromAnalysis, -to_analysis => $toAnalysis, -branch_code => $branch_code);
  Function: Constructor for DataflowRule object
  Returns : Bio::EnsEMBL::Hive::DataflowRule
  Args    : a rearrange-compatible hash
            
=cut

sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

    my ($fromAnalysis, $toAnalysis, $from_analysis_id, $branch_code, $funnel_dataflow_rule_id, $to_analysis_url, $input_id_template ) =
    rearrange( [ qw (FROM_ANALYSIS TO_ANALYSIS FROM_ANALYSIS_ID BRANCH_CODE FUNNEL_DATAFLOW_RULE_ID TO_ANALYSIS_URL INPUT_ID_TEMPLATE) ], @_ );

        # from objects:
    $self->from_analysis( $fromAnalysis )           if(defined($fromAnalysis));
    $self->to_analysis( $toAnalysis )               if(defined($toAnalysis));

        # simple scalars:
    $self->from_analysis_id($from_analysis_id)      if(defined($from_analysis_id));
    $self->to_analysis_url($to_analysis_url)        if(defined($to_analysis_url));
    $self->branch_code($branch_code)                if(defined($branch_code));
    $self->funnel_dataflow_rule_id($funnel_dataflow_rule_id)  if(defined($funnel_dataflow_rule_id));
    $self->input_id_template($input_id_template)    if(defined($input_id_template));

    return $self;
}


=head2 branch_code

    Function: getter/setter method for the branch_code of the dataflow rule

=cut

sub branch_code {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_branch_code'} = shift @_;
    }
    return $self->{'_branch_code'};
}


=head2 funnel_dataflow_rule_id

    Function: getter/setter method for the funnel_dataflow_rule_id of the dataflow rule

=cut

sub funnel_dataflow_rule_id {
    my $self = shift @_;

    if(@_) { # setter mode
        $self->{'_funnel_dataflow_rule_id'} = shift @_;
    }
    return $self->{'_funnel_dataflow_rule_id'};
}


=head2 input_id_template

    Function: getter/setter method for the input_id_template of the dataflow rule

=cut

sub input_id_template {
    my $self = shift @_;

    if(@_) { # setter mode
        my $input_id_template = shift @_;
        $self->{'_input_id_template'} = (ref($input_id_template) ? stringify($input_id_template) : $input_id_template),
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
  Returns : Bio::EnsEMBL::Hive::Analysis
  Args    : Bio::EnsEMBL::Hive::Analysis
  
=cut

sub from_analysis {
  my ($self,$analysis) = @_;

  # setter mode
  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Hive::Analysis')) {
      throw(
        "from_analysis arg must be a [Bio::EnsEMBL::Hive::Analysis]".
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
  Returns : Bio::EnsEMBL::Hive::Analysis
  Args    : Bio::EnsEMBL::Hive::Analysis
  
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

    my $ref_rule_adaptor = $self->from_analysis && $self->from_analysis->adaptor;

    if($analysis_or_nt->can('logic_name') and $ref_rule_adaptor and ($ref_rule_adaptor == $analysis_or_nt->adaptor)) {
      $self->{'_to_analysis_url'} = $analysis_or_nt->logic_name;
    } else {
      $self->{'_to_analysis_url'} = $analysis_or_nt->url($ref_rule_adaptor->db);
    }
  }
  # lazy load the analysis object if I can
  if(!defined($self->{'_to_analysis'}) and defined($self->to_analysis_url)) {

    my $url = $self->to_analysis_url;

    $self->{'_to_analysis'} = $self->adaptor
        ?  $self->adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name_or_url($url)
        :  Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor->fetch_by_logic_name_or_url($url)
    or die "Cannot fetch analysis from logic_name or url '$url' for dataflow rule with id='".$self->dbID."'\n";

  }
  return $self->{'_to_analysis'};
}


=head2 toString

  Args       : (none)
  Example    : print $df_rule->toString()."\n";
  Description: returns a stringified representation of the rule
  Returntype : string

=cut

sub toString {
    my $self = shift;

    return join('',
            'DataflowRule(dbID=',
            ($self->dbID || '?'),
            ($self->funnel_dataflow_rule_id ? ' --|| '.$self->funnel_dataflow_rule_id : ''),
            '): [#',
            $self->branch_code,
            '] ',
            $self->from_analysis->logic_name,
            ' -> ',
            $self->to_analysis_url,
            ($self->input_id_template ? (' WITH TEMPLATE: '.$self->input_id_template) : ''),
    );
}


1;

