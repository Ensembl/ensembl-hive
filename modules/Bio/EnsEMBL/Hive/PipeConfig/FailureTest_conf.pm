
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::FailureTest_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::FailureTest_conf -password <your_password>

    init_pipeline.pl FailureTest_conf.pm -pipeline_db -host=localhost -password <your_password> -job_count 100 -failure_rate 3

=head1 DESCRIPTION

    This is an example pipeline built around FailureTest.pm RunnableDB. It consists of two analyses:

    Analysis_1: JobFactory.pm is used to create an array of jobs -

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: FailureTest.pm either succeeds or dies, depending on the parameters.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::PipeConfig::FailureTest_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines three options:
                    o('job_count')          controls the total number of FailureTest jobs
                    o('failure_rate')       controls the rate of jobs that are programmed to fail
                    o('state')              controls the state in which the jobs will be failing
                    o('lethal_after')       when job_number is above this (nonzero) threshold, job's death becomes lethal to the Worker

                  There is a rule dependent on one option that does not have a default (this makes it mandatory):
                    o('password')           your read-write password for creation and maintenance of the hive database

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'failure_test',                  # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'job_count'         => 20,                                  # controls the total number of FailureTest jobs
        'failure_rate'      =>  3,                                  # controls the rate of jobs that are programmed to fail
        'state'             => 'RUN',                               # controls in which state the jobs are programmed to fail
        'lethal_after'      => 0,
    };
}

=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'generate_jobs'       generates a list of jobs

                    * 'failure_test'        either succeeds or fails, depending on parameters

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'generate_jobs',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputlist'    => '#expr([0..$job_count-1])expr#',    # this expression will evaluate into a listref
            },
            -input_ids => [
                {
                    'job_count'    => $self->o('job_count'),            # turn this option into a passable parameter
                    'failure_rate' => $self->o('failure_rate'),         # turn the other option into a passable parameter as well
                    'state'        => $self->o('state'),                # turn the third option into a passable parameter too
                    'lethal_after' => $self->o('lethal_after'),
                    'input_id' => { 'value' => '#_range_start#', 'divisor' => '#failure_rate#', 'state' => '#state#', 'lethal_after' => '#lethal_after#' },
                },
            ],
            -flow_into => {
                2 => [ 'failure_test' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'failure_test',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::FailureTest',
        },
    ];
}

1;

