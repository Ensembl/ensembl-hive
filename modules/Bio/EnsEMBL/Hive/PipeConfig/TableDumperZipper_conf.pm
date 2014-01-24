=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf -password $ENSADMIN_PSW -db_conn "mysql://ensadmin:${ENSADMIN_PSW}@localhost/lg4_long_mult"

    seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_zip_tables" -logic_name find_tables -input_id "{'only_tables' => '%_result'}"

    runWorker.pl -url mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_zip_tables
    runWorker.pl -url mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_zip_tables
    runWorker.pl -url mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_zip_tables

=head1 DESCRIPTION  

    This is an example pipeline put together from three analyses (with pre-existing Runnables) :

    Analysis_1: JobFactory.pm is used to turn the list of tables of the given database into jobs

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to dump individual tables; each flows via branch #1 into Analysis_3

    Analysis_3: another instance of SystemCmd.pm is used to compress an individual table dump file

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


package Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure (will be stringified and de-stringified automagically).

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class, then add our own stuff

        'db_conn'       => $self->o('db_conn'),
        'dumping_flags' => '-t',    # '-t' for "dump without table definition" or '' for "dump with table definition"
        'directory'     => '.',     # directory where both source and target files are located
        'matching_op'   => 'LIKE',  # 'LIKE' or 'NOT LIKE'
        'only_tables'   => '%',     # any wildcard understood by MySQL
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'find_tables'         generates a list of tables whose names match the pattern #only_tables#
                      Each job of this analysis will dataflow (create jobs) via branch #2 into 'table_dumper' analysis.

                    * 'table_dumper'        dumps table contents (possibly with table definition) and flows via branch #1 into 'file_compressor' analysis.

                    * 'file_compressor'     compresses the dump file

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'find_tables',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputquery'    => 'SELECT table_name FROM information_schema.tables WHERE table_schema = "#mysql_dbname:db_conn#" AND table_name #matching_op# "#only_tables#"',
            },
            -flow_into => {
#                2 => { 'table_dumper' => { 'table_name' => '#table_name#', 'db_conn' => '#db_conn#' }, },
                2 => [ 'table_dumper' ],
            },
        },

        {   -logic_name    => 'table_dumper',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'filename'   => '#directory#/#table_name#.sql',
                'cmd'        => 'mysqldump #mysql_conn:db_conn# #dumping_flags# #table_name# >#filename#',
            },
            -analysis_capacity => 2,
            -flow_into => {
#                1 => { 'file_compressor' => { 'filename' => '#filename#' }, },
                1 => [ 'file_compressor' ],
            },
        },

        {   -logic_name    => 'file_compressor',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'filename'   => '#directory#/#table_name#.sql',
                'cmd'        => 'gzip #filename#',
            },
            -analysis_capacity => 8,
        },
    ];
}

1;

