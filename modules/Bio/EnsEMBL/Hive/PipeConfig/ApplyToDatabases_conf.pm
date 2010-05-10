
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

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::PipeConfig::ApplyToDatabases_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'apply_to_databases',            # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'source_server1' => {
            -host   => 'ens-staging',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
        },

        'source_server2' => {
            -host   => 'ens-staging2',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
        },
        
        'only_databases'   => '%\_core\_%',                           # use '%' to get a list of all available databases
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'get_databases',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputquery' => q{SHOW DATABASES LIKE "}.$self->o('only_databases').q{"},
            },
            -hive_capacity => 5,       # allow several workers to perform identical tasks in parallel
            -input_ids => [
                { 'db_conn' => $self->o('source_server1'), 'input_id' => { 'db_conn' => {'-host' => $self->o('source_server1', '-host'), '-port' => $self->o('source_server1', '-port'), '-user' => $self->o('source_server1', '-user'), '-pass' => $self->o('source_server1', '-pass'), '-dbname' => '#_range_start#'}, }, },
                { 'db_conn' => $self->o('source_server2'), 'input_id' => { 'db_conn' => {'-host' => $self->o('source_server2', '-host'), '-port' => $self->o('source_server2', '-port'), '-user' => $self->o('source_server2', '-user'), '-pass' => $self->o('source_server2', '-pass'), '-dbname' => '#_range_start#'}, }, },
            ],
            -flow_into => {
                2 => [ 'dummy' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'dummy',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',  # use SqlCmd.pm to run your query or another JobFactory.pm to make another fan on table names
            -parameters    => {
            },
            -hive_capacity => 10,       # allow several workers to perform identical tasks in parallel
            -input_ids     => [
                # (jobs for this analysis will be flown_into via branch-2 from 'get_databases' jobs above)
            ],
        },
    ];
}

1;

