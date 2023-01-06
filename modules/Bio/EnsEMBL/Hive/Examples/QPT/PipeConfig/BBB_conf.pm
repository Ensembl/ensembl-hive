=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2023] EMBL-European Bioinformatics Institute

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

package Bio::EnsEMBL::Hive::Examples::QPT::PipeConfig::BBB_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow and INPUT_PLUS


sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name => 'call_CCC_or_DDD',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into => {
                '1->A'  => WHEN( '#a_multiplier# > #b_multiplier#'  => $self->o('CCC_url').'?logic_name=perform_task_X', ),
                'A->1'  => WHEN( '#a_multiplier# > #b_multiplier#'  => 'BBB_funnel', ),
                '1'     => WHEN( '#a_multiplier# <= #b_multiplier#' => [ 'perform_local_part', $self->o('DDD_url').'?logic_name=perform_task_Y', ],  ),
            },
        },

        {   -logic_name => 'perform_local_part',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },

        {   -logic_name => 'BBB_funnel',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into => {
                2 => '?accu_name=intermediate_result',
            },
        },
    ];
}

1;

