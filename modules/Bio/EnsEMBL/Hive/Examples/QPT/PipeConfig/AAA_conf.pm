=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::EnsEMBL::Hive::Examples::QPT::PipeConfig::AAA_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow and INPUT_PLUS



sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        $self->db_cmd('CREATE TABLE final_result (a_multiplier varchar(40) NOT NULL, b_multiplier varchar(40) NOT NULL, result varchar(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'),
    ];
}


sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name => 'call_BBB',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids => [
                { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788' },
                { 'a_multiplier' => '327358788', 'b_multiplier' => '9650156169' },
            ],
            -flow_into => {
                '1->A'  => $self->o('BBB_url').'?logic_name=call_CCC_or_DDD',
                'A->1'  => 'AAA_funnel',
            },
        },

        {   -logic_name => 'AAA_funnel',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into => {
                2 => '?table_name=final_result',
            },
        },
    ];
}

1;

