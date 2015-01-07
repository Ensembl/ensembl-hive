=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::ApplyToDatabases_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::ApplyToDatabases_conf -password <your_password>

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::ApplyToDatabases_conf -password <your_password> -only_databases '%'

=head1 DESCRIPTION  

    This is an example framework to run queries against databases whose names have been fetched from server:

    Analysis_1: JobFactory.pm is used to turn the list of databases on a particular mysql instance into jobs

    these jobs are sent down the branch #2 into the second analysis

    Analysis_2: Use SqlCmd.pm to run queries directly or another JobFactory.pm if you need a further fan on tables.

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


package Bio::EnsEMBL::Hive::PipeConfig::ApplyToDatabases_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        'pipeline_name' => 'apply_to_databases',            # name used by the beekeeper to prefix job names on the farm

        'source_server1' => 'mysql://ensadmin:'.$self->o('password').'@127.0.0.1:3306/',
        'source_server2' => 'mysql://ensadmin:'.$self->o('password').'@127.0.0.1:2914/',

        'only_databases'   => '%\_core\_%',                 # use '%' to get a list of all available databases
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'get_databases',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputquery'   => q{SHOW DATABASES LIKE "}.$self->o('only_databases').q{"},
                'column_names' => [ 'dbname' ],
            },
            -input_ids => [
                { 'db_conn' => $self->o('source_server1') },
                { 'db_conn' => $self->o('source_server2') },
            ],
            -flow_into => {
                2 => { 'run_sql' => { 'db_conn' => '#db_conn##dbname#' },
                }
            },
        },

        {   -logic_name    => 'run_sql',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',  # use SqlCmd.pm to run your query or another JobFactory.pm to make another fan on table names
            -parameters    => {
            },
            -analysis_capacity => 10,       # allow several workers to perform identical tasks in parallel
            -input_ids     => [
                # (jobs for this analysis will be flown_into via branch-2 from 'get_databases' jobs above)
            ],
        },
    ];
}

1;

