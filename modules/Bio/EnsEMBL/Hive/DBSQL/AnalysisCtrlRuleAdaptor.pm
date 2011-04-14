=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor 

=head1 SYNOPSIS

  $analysis_ctrl_rule_adaptor = $db_adaptor->get_AnalysisCtrlRuleAdaptor;
  $analysis_ctrl_rule_adaptor = $analysisCtrlRuleObj->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class AnalysisCtrlRule.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

use strict;
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;

use base ('Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor');


sub default_table_name {
    return 'analysis_ctrl_rule';
}


sub default_insertion_method {
    return 'INSERT_IGNORE';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::AnalysisCtrlRule';
}




=head2 remove_by_condition_analysis_url

  Arg[1]  : string condition_analysis_url
  Usage   : $self->remove_by_condition_analysis_url("ThisAnalysisLogicName");
  Function: removes all the control rules for this condition analysis URL
  Returns : -

  NB: This method is not called by ensembl-hive code itself,
  however it is used by two Compara pipeline modules,
        Bio/EnsEMBL/Compara/Production/GenomicAlignBlock/CreateAlignmentChainsJobs.pm
      and
        Bio/EnsEMBL/Compara/Production/GenomicAlignBlock/CreateAlignmentNetsJobs.pm
  in order to avoid blocking by an empty analysis. It should be re-written by using can_be_empty=1 analyses.

=cut

sub remove_by_condition_analysis_url {
  my ( $self, $condition_analysis_url ) = @_;

  my $sth = $self->prepare("DELETE FROM analysis_ctrl_rule WHERE condition_analysis_url =?");
  $sth->execute($condition_analysis_url);
}


=head2 create_rule

  Arg[1]      : condition analysis object (Bio::EnsEMBL::Analysis object)
  Arg[2]      : controled analysis object (Bio::EnsEMBL::Analysis object)
  Example     : $dba->get_AnalysisCtrlRuleAdaptor->create_rule($conditionAnalysis, $ctrledAnalysis);
  Description : Creates an AnalysisCtrlRule where the condition analysis must be completely DONE with
                all jobs in order for the controlled analysis to be unblocked and allowed to proceed.
                If an analysis requires multiple conditions, simply create multiple rules and controlled
                analysis will only unblock if ALL conditions are satisified.
  Returntype  : none
  Exceptions  : none
  Caller      : HiveGeneric_conf.pm and various pipeline-creating scripts
  
=cut

sub create_rule {
    my ($self, $conditionAnalysis, $ctrledAnalysis) = @_;

    return unless($conditionAnalysis and $ctrledAnalysis);

    my $rule = Bio::EnsEMBL::Hive::AnalysisCtrlRule->new();
    # NB: ctrled_analysis must be set first in order for internal logic to abbreviate 'to_url'
    $rule->ctrled_analysis($ctrledAnalysis);
    $rule->condition_analysis($conditionAnalysis);

    return $self->store($rule, 1);  # avoid redundancy
}


1;
