# Perl module for Bio::EnsEMBL::Hive::DataflowRule
#
# Creator: Jessica Severin <jessica@ebi.ac.uk>
# Date of creation: 22.03.2004
#
# Copyright EMBL-EBI 2000-2004
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

  Bio::EnsEMBL::Hive::DataflowRule

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


package Bio::EnsEMBL::Hive::DataflowRule;

use strict;
use Bio::EnsEMBL::Utils::Argument;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Hive::URLFactory;


=head2 Constructor

  Title   : new
  Usage   : ...DataflowRule->new($analysis);
  Function: Constructor for DataflowRule object
  Returns : Bio::EnsEMBL::Hive::DataflowRule
  Args    : A Bio::EnsEMBL::Analysis object. Conditions are added later,
            adaptor and dbid only used from the adaptor.
            
=cut


sub new {
  my ($class,@args) = @_;
  my $self = bless {}, $class;

  my ( $dbID, $adaptor, $fromAnalysis, %fromID, $toAnalysis, $toURL ) =
    rearrange( [ qw (DBID ADAPTOR FROM_ANALYSIS FROM_ID TO_ANALYSIS TO_URL) ], @args );
    
  $self->dbID($dbID) if(defined($dbID));
  $self->adaptor($adaptor) if(defined($adaptor));
  $self->from_analysis($fromAnalysis) if(defined($fromAnalysis));
  $self->to_analysis($toAnalysis ) if(defined($toAnalysis));

  return $self;
}

sub dbID {
  my ( $self, $dbID ) = @_;
  $self->{'_dbID'} = $dbID if defined $dbID;
  return $self->{'_dbID'};
}

sub adaptor {
  my ( $self, $adaptor ) = @_;
  $self->{'_adaptor'} = $adaptor if defined $adaptor;
  return $self->{'_adaptor'};
}


=head2 branch_code

  Title   : branch_code
  Arg[1]  : (optional) int $code
  Usage   : $self->branch_code($code);
  Function: Get/set method for rules branch_code.
  Returns : integer
  
=cut

sub branch_code {
  #default branch_code = 1
  my( $self, $value ) = @_;
  $self->{'_branch_code'} = 1 unless(defined($self->{'_branch_code'}));
  $self->{'_branch_code'} = $value if(defined($value));
  return $self->{'_branch_code'};
}


=head2 from_analysis_id

  Title   : from_analysis_id
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

  Title   : to_analysis_url
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

  Title   : from_analysis
  Usage   : $self->from_analysis($anal);
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

  Title   : to_analysis
  Usage   : $self->to_analysis($anal);
  Function: Get/set method for the goal analysis object of this rule.
  Returns : Bio::EnsEMBL::Analysis
  Args    : Bio::EnsEMBL::Analysis
  
=cut

sub to_analysis {
  my ($self,$analysis) = @_;

  if( defined $analysis ) {
    unless ($analysis->isa('Bio::EnsEMBL::Analysis')) {
      throw(
        "to_analysis arg must be a [Bio::EnsEMBL::Analysis]".
        "not a [$analysis]");
    }
    $self->{'_to_analysis'} = $analysis;

    #if the 'from' and 'to' share the same adaptor, then use a simple logic_name
    #for the URL rather than a full network distributed URL
    if($self->from_analysis and ($self->from_analysis->adaptor == $analysis->adaptor)) {
      $self->{'_to_analysis_url'} = $analysis->logic_name;
    } else {
      $self->{'_to_analysis_url'} = $analysis->url;
    }
  }
  # lazy load the analysis object if I can
  if(!defined($self->{'_to_analysis'}) and defined($self->to_analysis_url)) {
    my $analyis =  Bio::EnsEMBL::Hive::URLFactory->fetch($self->to_analysis_url);
    unless($analysis) {
      $analysis =
        $self->adaptor->db->get_AnalysisAdaptor->fetch_by_logic_name($self->to_analysis_url);
    }
    $self->{'_to_analysis'} = $analysis;
      
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



