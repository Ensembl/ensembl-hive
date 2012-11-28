
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::RunListOfCommandsOnFarm_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::RunListOfCommandsOnFarm_conf -password <your_password> -inputfile file_with_cmds.txt

=head1 DESCRIPTION

    This is an example pipeline put together from basic building blocks:

    Analysis_1: JobFactory.pm is used to turn the list of commands in a file into jobs

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to run these jobs in parallel.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::PipeConfig::RunListOfCommandsOnFarm_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines three options:
                    o('capacity')   defines how many files can be run in parallel
                
                  There are rules dependent on two options that do not have defaults (this makes them mandatory):
                    o('password')           your read-write password for creation and maintenance of the hive database
                    o('inputfile')          name of the inputfile where the commands are

=cut

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        'pipeline_name' => 'ifile_syscmd',                  # name used by the beekeeper to prefix job names on the farm

        'capacity'  => 100,                                 # how many commands can be run in parallel
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'create_jobs'  reads commands line-by-line from inputfile
                      Each job of this analysis will dataflow (create jobs) via branch #2 into 'run_cmd' analysis.

                    * 'run_cmd'   actually runs the commands in parallel

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'create_jobs',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'column_names' => [ 'cmd' ],
            },
            -input_ids => [
                { 'inputfile' => $self->o('inputfile') },   # A new file-with-commands could be loaded at each -topup_jobs execution of init_pipeline
            ],
            -flow_into => {
                2 => [ 'run_cmd' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'run_cmd',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => { },
            -analysis_capacity => $self->o('capacity'),   # allow several workers to perform identical tasks in parallel
        },
    ];
}

1;

