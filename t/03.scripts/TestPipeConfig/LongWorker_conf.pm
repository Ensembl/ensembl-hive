=pod

=head1 NAME

    TestPipeConfig::LongWorker_conf

=head1 SYNOPSIS

    init_pipeline.pl TestPipeConfig::LongWorker_conf -password <your_password>

=head1 DESCRIPTION

    This is an example pipeline that creates long-running jobs, mainly for testing:

    Analysis_1: JobFactory.pm is used to create an array of jobs -

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: Dummy.pm using take_time to set the length of time a job should run

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2020] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package TestPipeConfig::LongWorker_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


sub resource_classes {
    my ($self) = @_;
    return {
        %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
        'default'      => {'LSF' => '-C0 -M100   -R"select[mem>100]   rusage[mem=100]"' },
    };
}


sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'generate_jobs',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -meadow_type => 'LOCAL',
            -parameters => {
                'column_names' => [ 'take_time' ],
            },
            -input_ids => [
                { 'inputlist' => [ 120, 240 ], },
            ],

            -flow_into => {
                2 => [ 'longrunning' ],
            },
        },

        {   -logic_name    => 'longrunning',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -rc_name => 'default',      # pick a valid value from resource_classes() section
        },
    ];
}

1;
