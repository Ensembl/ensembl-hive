package Bio::EnsEMBL::Hive::Examples::QPT::PipeConfig::CCC_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow and INPUT_PLUS


sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name => 'perform_task_X',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into => {
                2 => '?accu_name=intermediate_result',
            },
        },
    ];
}

1;

