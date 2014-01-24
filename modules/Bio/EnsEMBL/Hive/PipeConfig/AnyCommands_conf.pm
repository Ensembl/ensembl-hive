=pod

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf -password <your_password>

    seed_pipeline.pl -url $HIVE_URL -logic_name perform_cmd -input_id "{'cmd' => 'gzip pdfs/RondoAllaTurca_Mozart_Am.pdf; sleep 5'}"

    runWorker.pl -url $HIVE_URL

    seed_pipeline.pl -url $HIVE_URL -logic_name perform_cmd -input_id "{'cmd' => 'gzip -d pdfs/RondoAllaTurca_Mozart_Am.pdf.gz ; sleep 4'}"

    runWorker.pl -url $HIVE_URL

=head1 DESCRIPTION

    This is the smallest Hive pipeline example possible.
    The pipeline has only one analysis, which can run any shell command defined in each job by setting its 'cmd' parameter.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub pipeline_analyses {
    return [
        {   -logic_name    => 'perform_cmd',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        },
    ];
}

1;

