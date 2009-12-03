# Perl module for Bio::EnsEMBL::Hive::AnalysisCtrlRule
#
# Creator: Jessica Severin <jessica@ebi.ac.uk>
# Date of creation: 22.03.2004
#
# Copyright EMBL-EBI 2000-2004
#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::AnalysisCtrlRule

=head1 SYNOPSIS

=head1 DESCRIPTION

  An 'analysis control rule' is a high level blocking control structure where there is
  a 'ctrled_analysis' which is 'BLOCKED' from running until all of its 'condition_analysis' are 'DONE'.
  If a ctrled_analysis requires multiple analysis to be DONE before it can run, a separate
  AnalysisCtrlRule must be created/stored for each condtion analysis.
  
  Allows the 'condition' analysis to be specified with a network savy URL like
  mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test?analysis.logic_name='blast_NCBI34'


=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut



package Bio::EnsEMBL::Hive::AnalysisCtrlRule;

use strict;
use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::Extensions;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;

=head2 Constructor

  Title   : new
  Usage   : ...AnalysisCtrlRule->new;
  Function: Constructor for empty AnalysisCtrlRule object
  Returns : Bio::EnsEMBL::Hive::AnalysisCtrlRule
  Args    : none
  
=cut

sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;
  
  return $self;
}

sub adaptor {
  my ( $self, $adaptor ) = @_;
  $self->{'_adaptor'} = $adaptor if defined $adaptor;
  return $self->{'_adaptor'};
}


=head2 ctrled_analysis_id

  Arg[1]  : (optional) int $dbID
  Usage   : $self->ctrled_analysis_id($dbID);
  Function: Get/set method for the analysis which will be BLOCKED until all
            of its condition analyses are 'DONE'. Specified as a dbID.
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

  Arg[1]  : (optional) string $url
  Usage   : $self->condition_analysis_url($url);
  Function: Get/set method for the analysis which must be 'DONE' in order for
            the controlled analysis to be un-BLOCKED. Specified as a URL.
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

  Arg[1]  : (optional) Bio::EnsEMBL::Analysis object
  Usage   : $self->ctrled_analysis($anal);
  Function: Get/set method for the analysis which will be BLOCKED until all
            of its condition analyses are 'DONE'
  Returns : Bio::EnsEMBL::Analysis
  
=cut

sub ctrled_analysis {
  my ($self,$analysis) = @_;

  # setter mode
  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      throw(
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

  Arg[1]  : (optional) Bio::EnsEMBL::Analysis object
  Usage   : $self->condition_analysis($anal);
  Function: Get/set method for the analysis which must be 'DONE' in order for
            the controlled analysis to be un-BLOCKED
  Returns : Bio::EnsEMBL::Analysis
  
=cut

sub condition_analysis {
  my ($self,$analysis) = @_;

  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      throw(
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


=head2 print_rule

  Usage   : $ctrlRule->print_rule;
  Function: Prints a description of the rule for use in debugging.
  
=cut

sub print_rule {
  my $self = shift;
  print("AnalysisCtrlRule ",
        "  ctrled_analysis_id=", $self->ctrled_analysis_id,
        "  condition_analysis_url=", $self->condition_analysis_url,
        "\n");
}

1;



