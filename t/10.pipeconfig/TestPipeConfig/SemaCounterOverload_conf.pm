=pod

=head1 NAME

    TestPipeConfig::SemaCounterOverload_conf

=head1 DESCRIPTION

    This is a PipeConfig for a special "stress-inducing" pipeline that intentionally creates a very high load
    on the semaphore counters to assess the behaviour and efficiency of or our deadlock-avoiding approaches.

    It has to be "pessimized" for a specific farm/cluster (EBI RH7), so does not take part in an automatic test and is run manually.

    In order to create deadlocks comment out the prelock_ calls before inserting a Job in AnalysisJobAdaptor,
    then run two separate workers to saturate the 'fan_C' analysis (takes under a minunte),
    and finally submit 300 Workers of analysis 'fan_C' in one go by running beepeeker.pl with "-submit_workers_max 300 -run" .

    You get the best results (more collisions) when the farm is not busy and all the 300 workers run in parallel.

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


package TestPipeConfig::SemaCounterOverload_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow and INPUT_PLUS


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },

        'time'              => '40+30*rand(1)',
        'num_semaphores'    => 1,
        'num_per_sem'       => 3000,
        'capacity'          => 300,
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'factory_A',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -meadow_type => 'LOCAL',
            -parameters => {
                'inputlist'    => '#expr([1..#num_semaphores#])expr#',
                'column_names' => [ 'sem_index' ],
            },
            -input_ids => [
                { 'num_semaphores' => $self->o('num_semaphores') },
            ],
            -analysis_capacity => 1,
            -flow_into => {
                '2->A' => 'factory_B',
                'A->1' => 'funnel_E',
            },
        },

        {   -logic_name     => 'factory_B',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters     => {
                'inputlist'     => '#expr([1..#num_per_sem#])expr#',
                'column_names'  => [ 'sem_subindex' ],
                'num_per_sem'   => $self->o('num_per_sem'),
            },
            -flow_into => {
                '2' => { 'fan_C' => INPUT_PLUS() },
            }
        },

        {   -logic_name    => 'fan_C',
            -module        => 'TestRunnable::TransactDummy',
            -hive_capacity  => $self->o('capacity'),
            -parameters    => {
                'take_time'         => $self->o('time'),
            },
            -flow_into => {
                '1' => 'fan_D',
            }
        },

        {   -logic_name    => 'fan_D',
            -module        => 'TestRunnable::TransactDummy',
            -hive_capacity  => $self->o('capacity'),
            -parameters    => {
                'take_time'         => $self->o('time'),
            },
        },

        {   -logic_name    => 'funnel_E',
            -module        => 'TestRunnable::TransactDummy',
        },
    ];
}

1;
