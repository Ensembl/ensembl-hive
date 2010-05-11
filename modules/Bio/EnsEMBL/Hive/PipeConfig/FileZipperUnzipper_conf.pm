
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::FileZipperUnzipper_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::FileZipperUnzipper_conf -password <your_password> -directory $HOME/ncbi_taxonomy -unzip 1

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::FileZipperUnzipper_conf -password <your_password> -directory directory_with_huge_dumps -only_files '*.sql'

=head1 DESCRIPTION

    This is an example pipeline put together from basic building blocks:

    Analysis_1: JobFactory.pm is used to turn the list of files in a given directory into jobs

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to run these compression/decompression jobs in parallel.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::PipeConfig::FileZipperUnzipper_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines three options:
                    o('unzip')              controls whether the files will be zipped or unzipper (zipped by default)
                    o('only_files')         defines which files in the directory will be (un)zipped
                    o('zipping_capacicy')   defines how many files can be zipped in parallel
                
                  There are rules dependent on two options that do not have defaults (this makes them mandatory):
                    o('password')           your read-write password for creation and maintenance of the hive database
                    o('directory')          name of the directory where the files are to be (un)zipped

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'zip_unzip_files',               # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'unzip'             => 0,                                   # set to '1' to switch to decompression
        'only_files'        => '*',                                 # use '*.sql*' to only (un)zip these files
        'zipping_capacity'  => 10,                                  # how many files can be (un)zipped in parallel
    };
}

=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  It is just the standard stuff, so we could have as well omitted this method altogether.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation
    ];
}

=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'get_files'  generates a list of files whose names match the pattern o('only_files')
                      Each job of this analysis will dataflow (create jobs) via branch #2 into 'zipper_unzipper' analysis.

                    * 'zipper_unzipper'   actually performs the (un)zipping of the files in parallel

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'get_files',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputcmd' => 'find '.$self->o('directory').' -type f -name "'.$self->o('only_files').'"',
            },
            -input_ids => [
                { 'input_id' => { 'filename' => '#_range_start#' }, },
            ],
            -flow_into => {
                2 => [ 'zipper_unzipper' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'zipper_unzipper',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'cmd'       => 'gzip '.($self->o('unzip')?'-d ':'').'#filename#',
            },
            -hive_capacity => $self->o('zipping_capacity'),   # allow several workers to perform identical tasks in parallel
            -input_ids     => [
                # (jobs for this analysis will be flown_into via branch-2 from 'get_tables' jobs above)
            ],
        },
    ];
}

1;

