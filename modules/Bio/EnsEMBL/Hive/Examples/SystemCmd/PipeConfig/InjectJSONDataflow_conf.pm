=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::SystemCmd::PipeConfig::InjectJSONDataflow_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::SystemCmd::PipeConfig::InjectJSONDataflow_conf --pipeline_url $HIVE_URL

    seed_pipeline.pl -url $HIVE_URL -logic_name perform_cmd -input_id "{'cmd' => 'sleep 0', 'dataflow_file' => './sample_files/Inject_JSON_Dataflow_example.json'}"

    runWorker.pl -url $HIVE_URL

=head1 DESCRIPTION

    This is an example of using the SystemCmd runnable to create dataflow events using parameters read from a JSON file.
    There is a sample file located in ${EHIVE_ROOT_DIR}/modules/Bio/EnsEMBL/Hive/Examples/SystemCmd/PipeConfig/sample_files/
    This file is called Inject_JSON_Dataflow_example.json

    Each line of this file contains an optional branch number, followed by a complete JSON serialisation of the parameters (output_id)
    appearing on the same line. For example, a line to direct dataflow on branch 2 might look like:

          2 {"parameter_name" : "parameter_value"}

    If no branch number is provided, then dataflow of those parameters will occour on the branch number
    passed to SystemCmd in the 'dataflow_branch' parameter, if given. Otherwise, it will default to
    branch 1 (autoflow).

    Note that a command must be provided to SystemCmd using the 'cmd' parameter, even if JSON parameter injection
    is the only desired behaviour.


=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Examples::SystemCmd::PipeConfig::InjectJSONDataflow_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub pipeline_analyses {
    return [
        {   -logic_name    => 'perform_cmd',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -flow_into     => {
                    1 => ['autoflow_test'],
                    2 => ['branch2_test'],
                    3 => ['branch3_test'],
                    4 => ['branch4_test'],
            },
        },
        {   -logic_name    => 'autoflow_test',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
        {   -logic_name    => 'branch2_test',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
        {   -logic_name    => 'branch3_test',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
        {   -logic_name    => 'branch4_test',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
    ];
}

1;

