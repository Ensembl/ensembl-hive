=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor 

=head1 SYNOPSIS

    $analysis_ctrl_rule_adaptor = $db_adaptor->get_AnalysisCtrlRuleAdaptor;
    $analysis_ctrl_rule_adaptor = $analysisCtrlRuleObj->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class AnalysisCtrlRule.
    There should be just one per application and database connection.

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

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor;

use strict;
use warnings;
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

