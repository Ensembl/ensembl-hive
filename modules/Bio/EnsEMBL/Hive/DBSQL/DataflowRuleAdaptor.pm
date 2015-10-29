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

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::DataflowRule;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub check_object_present_in_db_by_content {
    return 0;
}


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

1;

