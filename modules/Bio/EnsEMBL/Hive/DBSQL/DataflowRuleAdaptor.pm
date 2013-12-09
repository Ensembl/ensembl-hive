=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor 

=head1 SYNOPSIS

    $dataflow_rule_adaptor = $db_adaptor->get_DataflowRuleAdaptor;
    $dataflow_rule_adaptor = $dataflowRuleObj->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class DataflowRule.
    There should be just one per application and database connection.

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


package Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use strict;
use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::DataflowRule;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'dataflow_rule';
}


sub default_insertion_method {
    return 'INSERT';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::DataflowRule';
}


=head2 branch_name_2_code

Description: encodes a branch mnemonic name into numeric code

=cut

sub branch_name_2_code {

    shift @_ if(ref($_[0]));     # skip the first argument if it is an object, so it works both as a method and a subroutine

    my ($branch_name_or_code, $no_default) = @_;

    return ($no_default ? undef : 1) unless(defined($branch_name_or_code));

    my $branch_code = ($branch_name_or_code=~/^\-?\d+$/)
        ? $branch_name_or_code
        : {
            'MAIN'          =>  1,

            'ANYFAILURE'    =>  0,
            'MEMLIMIT'      => -1,
            'RUNLIMIT'      => -2,
        }->{$branch_name_or_code};
    return defined($branch_code) ? $branch_code : die "Could not map the branch_name '$branch_name_or_code' to the internal code";
}


=head2 fetch_all_by_from_analysis_id_and_branch_code

  Args       : unsigned int $analysis_id, unsigned int $branch_code
  Example    : my @rules = @{$ruleAdaptor->fetch_all_by_from_analysis_id_and_branch_code($analysis_id, $branch_code)};
  Description: searches database for rules with given from_analysis_id and branch_code
               and returns all such rules in a list (by reference)
  Returntype : reference to list of Bio::EnsEMBL::Hive::DataflowRule objects
  Exceptions : none
  Caller     : Bio::EnsEMBL::Hive::AnalysisJob::dataflow_output_id

=cut

sub fetch_all_by_from_analysis_id_and_branch_code {
    my ($self, $analysis_id, $branch_name_or_code) = @_;

    return [] unless($analysis_id);

    my $branch_code = $self->branch_name_2_code($branch_name_or_code);

    my $constraint = "from_analysis_id=${analysis_id} AND branch_code=${branch_code}";

    return $self->fetch_all($constraint);
}


1;

