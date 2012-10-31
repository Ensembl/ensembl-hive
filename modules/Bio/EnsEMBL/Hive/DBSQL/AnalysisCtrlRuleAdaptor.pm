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

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'analysis_ctrl_rule';
}


sub default_insertion_method {
    return 'INSERT_IGNORE';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::AnalysisCtrlRule';
}


1;

