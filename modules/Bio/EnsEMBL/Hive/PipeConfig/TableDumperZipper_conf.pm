
=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf -password <your_password> -source_dbname ncbi_taxonomy

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf -password <your_password> -source_dbname avilella_compara_homology_58 -only_tables 'protein_tree%' -with_schema 0

=head1 DESCRIPTION  

    This is an example pipeline put together from basic building blocks:

    Analysis_1: JobFactory.pm is used to turn the list of tables of the given database into jobs

    these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to run these dumping+compression jobs in parallel.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::PipeConfig::TableDumperZipper_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'zip_tables',                    # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'source_db' => {
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => $self->o('source_dbname'),
        },
        
        'with_schema'   => 1,                                           # include table creation statement before inserting the data
        'only_tables'   => '%',                                         # use 'protein_tree%' or 'analysis%' to only dump those tables
        'target_dir'    => $ENV{'HOME'}.'/'.$self->o('source_dbname'),  # where we want the compressed files to appear
    };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

        'mkdir -p '.$self->o('target_dir'),
    ];
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'get_tables',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'    => $self->o('source_db'),
                'inputquery' => 'SHOW TABLES LIKE "'.$self->o('only_tables').'"',
                'numeric'    => 0,
            },
            -input_ids => [
                { 'input_id' => { 'table_name' => '$RangeStart' }, },
            ],
            -flow_into => {
                2 => [ 'dumper_zipper' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'dumper_zipper',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'target_dir' => $self->o('target_dir'),
                'cmd'        => 'mysqldump '.$self->dbconn_2_mysql('source_db', 0).' '.$self->o('source_db','-dbname').($self->o('with_schema')?'':' -t').' #table_name# | gzip >#target_dir#/#table_name#.sql.gz',
            },
            -hive_capacity => 10,       # allow several workers to perform identical tasks in parallel
            -input_ids     => [
                # (jobs for this analysis will be flown_into via branch-2 from 'get_tables' jobs above)
            ],
        },
    ];
}

1;

