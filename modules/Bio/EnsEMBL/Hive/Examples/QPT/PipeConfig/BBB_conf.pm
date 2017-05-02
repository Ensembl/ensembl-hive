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

