=pod

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf -password <your_password>

    seed_pipeline.pl -url <url> -logic_name find_files -input_id "{ 'directory' => 'dumps' }"

=head1 DESCRIPTION

    This is an example pipeline put together from two basic building blocks:

    Analysis_1: JobFactory.pm is used to turn the list of files in a given directory into jobs

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to run these compression/decompression jobs in parallel.

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


package Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'find_files'          generates a list of files whose names match the pattern #only_files#
                                            Each job of this analysis will dataflow (create jobs) via branch #2 into 'compress_a_file' analysis.

                    * 'compress_a_file'     actually performs the (un)gzipping of the files in parallel

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'find_files',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputcmd'     => 'find #directory# -type f',
                'column_names' => [ 'filename' ],
            },
            -flow_into => {
                2 => [ 'compress_a_file' ],     # will create a fan of jobs
            },
        },

        {   -logic_name    => 'compress_a_file',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'cmd'       => 'gzip #filename#',
            },
            -analysis_capacity => 4,            # limit the number of workers that will be performing jobs in parallel
        },
    ];
}

1;

