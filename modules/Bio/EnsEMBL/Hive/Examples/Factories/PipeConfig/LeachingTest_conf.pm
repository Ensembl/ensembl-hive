=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LeachingTest_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LeachingTest_conf -password <your_password>

=head1 DESCRIPTION

    When we attempt to create a new semaphored group of jobs and the creation of the funnel job fails
    because there is already a job with the same primary key, we reuse this funnel job and simply top up
    the semaphore group with extra fan jobs. This is what we call "leaching".

    This is a small pipeline to test leaching via using templates.

    Note 1: this is not the recommended way to create a single backbone from multiple independent streams!

    Note 2: the 'start' analysis is only needed because of the recently adopted rule of automatically param-stacking
            the very first job that does not have a local parent (used mainly for maintaining cross-database return capability,
            but could prove itself useful in other contexts as well). If/when we decide against this feature,
            we can also drop the 'start' analysis, leaving two independent seeding jobs in 'factory' analysis
            and changing the leeching.t test accordingly (removing one execution of runWorker).

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::LeachingTest_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'start',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -input_ids => [
                {},
            ],
            -flow_into => {
                1 => {
                    'factory' => [ {'inputlist' => [ 11, 33, 55, 66, 77 ]}, {'inputlist' => [22, 44, 55, 66 ]} ],
                    'aggregator' => {},
                },
            },
        },

        {   -logic_name => 'factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'column_names' => [ 'alpha' ],
            },
            -flow_into => {                                         # There are two input jobs...
                '2->A'  => 'fan',
                'A->1'  => { 'funnel' => { 'funnel_id' => 7 }},     # ...however we want all of the children to report to one common funnel
            },
        },

        {   -logic_name    => 'fan',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into => {
                1 => '?accu_name=alphas&accu_input_variable=alpha&accu_address=[]',
            },
        },

        {   -logic_name    => 'funnel',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'alpha_csv' => '#expr( join(",", @{#alphas#}) )expr#',
                'cmd'       => 'echo "#alpha_csv#"',
            },
            -flow_into => {
                '1->A' => 'fan',
                'A->1' => { 'aggregator' => {}, },
            },
        },

        {   -logic_name    => 'aggregator',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
    ];
}

1;
