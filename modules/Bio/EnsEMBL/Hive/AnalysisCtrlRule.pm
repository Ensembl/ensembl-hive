# Perl module for Bio::EnsEMBL::Hive::AnalysisCtrlRule
#
# Creator: Jessica Severin <jessica@ebi.ac.uk>
# Date of creation: 22.03.2004
#
# Copyright EMBL-EBI 2000-2004
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME
  Bio::EnsEMBL::Hive::AnalysisCtrlRule

=head1 SYNOPSIS

=head1 DESCRIPTION
  Needed a robust and simpler rule table
  where Analyses in the pipeline can robustly define
  new analyses and rules.  New design has a single table where a 'rule'
  is a simple link from one analysis to another.
  Extended from design of SimpleRule concept to allow the 'to' analysis to
  be specified with a network savy URL like
  mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test?analysis.logic_name='blast_NCBI34'


=head1 CONTACT
  Contact Jessica Severin on EnsEMBL::Hive implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX
  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Hive::AnalysisCtrlRule;

use vars qw(@ISA);
use Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::Extensions;
use strict;

@ISA = qw( Bio::EnsEMBL::Root );

=head2 Constructor

  Title   : new
  Usage   : ...AnalysisCtrlRule->new;
  Function: Constructor for empty AnalysisCtrlRule object
  Returns : Bio::EnsEMBL::Hive::AnalysisCtrlRule
  Args    : none
=cut

sub new {
  my ($class,@args) = @_;
  my $self = $class->SUPER::new(@args);

  return $self;
}

sub adaptor {
  my ( $self, $adaptor ) = @_;
  $self->{'_adaptor'} = $adaptor if defined $adaptor;
  return $self->{'_adaptor'};
}


=head2 ctrled_analysis_id
  Title   : ctrled_analysis_id
  Arg[1]  : (optional) int $dbID
  Usage   : $self->ctrled_analysis_id($dbID);
  Function: Get/set method for the 'controlled' analysis objects dbID of this rule.
  Returns : integer
=cut
sub ctrled_analysis_id {
  my ($self,$analysis_id) = @_;
  if($analysis_id) {
    $self->{'_ctrled_analysis_id'} = $analysis_id;
    $self->{'_ctrled_analysis'} = undef;
  }
  return $self->{'_ctrled_analysis_id'};
}


=head2 condition_analysis_url
  Title   : condition_analysis_url
  Arg[1]  : (optional) string $url
  Usage   : $self->condition_analysis_url($url);
  Function: Get/set method for the 'to' analysis objects URL for this rule
  Returns : string
=cut
sub condition_analysis_url {
  my ($self,$url) = @_;
  if($url) {
    $self->{'_condition_analysis_url'} = $url;
    $self->{'_condition_analysis'} = undef;
  }
  return $self->{'_condition_analysis_url'};
}


=head2 ctrled_analysis
  Title   : ctrled_analysis
  Usage   : $self->ctrled_analysis($anal);
  Function: Get/set method for the condition analysis object of this rule.
  Returns : Bio::EnsEMBL::Analysis
  Args    : Bio::EnsEMBL::Analysis
=cut
sub ctrled_analysis {
  my ($self,$analysis) = @_;

  # setter mode
  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      $self->throw(
        "ctrled_analysis arg must be a [Bio::EnsEMBL::Analysis]".
        "not a [$analysis]");
    }
    $self->{'_ctrled_analysis'} = $analysis;
    $self->{'_ctrled_analysis_id'} = $analysis->dbID;
  }
  
  # lazy load the analysis object if I can
  if(!defined($self->{'_ctrled_analysis'})
     and defined($self->ctrled_analysis_id)
     and defined($self->adaptor))
  {
    $self->{'_ctrled_analysis'} =
      $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->ctrled_analysis_id);
  }
  return $self->{'_ctrled_analysis'};
}


=head2 condition_analysis
  Title   : condition_analysis
  Usage   : $self->condition_analysis($anal);
  Function: Get/set method for the goal analysis object of this rule.
  Returns : Bio::EnsEMBL::Analysis
  Args    : Bio::EnsEMBL::Analysis
=cut
sub condition_analysis {
  my ($self,$analysis) = @_;

  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      $self->throw(
        "condition_analysis arg must be a [Bio::EnsEMBL::Analysis]".
        "not a [$analysis]");
    }
    $self->{'_condition_analysis'} = $analysis;

    #if the 'condition' and 'ctrled' share the same adaptor, then use a simple logic_name
    #for the URL rather than a full network distributed URL
    if($self->ctrled_analysis and ($self->ctrled_analysis->adaptor == $analysis->adaptor)) {
      $self->{'_condition_analysis_url'} = $analysis->logic_name;
    } else {
      $self->{'_condition_analysis_url'} = $analysis->url;
    }
  }
  # lazy load the analysis object if I can
  if(!defined($self->{'_condition_analysis'}) and defined($self->condition_analysis_url)) {
    $analysis =  Bio::EnsEMBL::Hive::URLFactory->fetch($self->condition_analysis_url);
    unless($analysis) {
      $analysis =
        $self->adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name($self->condition_analysis_url);
    }
    $self->{'_condition_analysis'} = $analysis;
      
  }
  return $self->{'_condition_analysis'};
}

sub print_rule {
  my $self = shift;
  print("AnalysisCtrlRule ",
        "  ctrled_analysis_id=", $self->ctrled_analysis_id,
        "  condition_analysis_url=", $self->condition_analysis->url,
        "\n");
}

1;



