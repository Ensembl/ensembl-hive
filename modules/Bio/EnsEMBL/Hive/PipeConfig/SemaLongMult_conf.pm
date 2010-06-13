
=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::SemaLongMult_conf;

=head1 SYNOPSIS

       # Example 1: specifying only the mandatory option:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::SemaLongMult_conf -password <mypass>

       # Example 2: specifying the mandatory options as well as overriding some defaults:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::SemaLongMult_conf -password <mypass> -first_mult 2344556 -second_mult 777666555

=head1 DESCRIPTION

    This is the PipeConfig file for the *semaphored* long multiplication pipeline example.
    The main point of this pipeline is to provide an example of how to set up job-level semaphored control instead of using analysis-level control rules.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf to understand how long multiplication pipeline works in its original form.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::SemaLongMult_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines two options, 'first_mult' and 'second_mult' that are supposed to contain the long numbers to be multiplied.

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'sema_long_mult',                # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'first_mult'    => '9650516169',                    # the actual numbers that will be multiplied must also be possible to specify from the command line
        'second_mult'   =>  '327358788',
    };
}

=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates two pipeline-specific tables used by Runnables to communicate.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE intermediate_result (a_multiplier char(40) NOT NULL, digit tinyint NOT NULL, result char(41) NOT NULL, PRIMARY KEY (a_multiplier, digit))'",
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'",
    ];
}

=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:

                    * 'sema_start' with two jobs (multiply 'first_mult' by 'second_mult' and vice versa - to check the commutativity of multiplivation).
                      Each job will dataflow (create more jobs) via branch #2 into 'part_multiply' and via branch #1 into 'add_together'.

                      Unlike LongMult_conf, there is no analysis-level control here, but SemaStart analysis itself is more intelligent
                      in that it can dataflow a group of partial multiplication jobs in branch #2 linked with one job in branch #1 by a semaphore.

                    * 'part_multiply' initially without jobs (they will flow from 'start')

                    * 'add_together' initially without jobs (they will flow from 'start').
                      Unlike LongMult_conf here we do not use analysis control and rely on job-level semaphores to keep the jobs in sync.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'sema_start',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::SemaStart',
            -parameters => {},
            -input_ids => [
                { 'a_multiplier' => $self->o('first_mult'),  'b_multiplier' => $self->o('second_mult') },
                { 'a_multiplier' => $self->o('second_mult'), 'b_multiplier' => $self->o('first_mult')  },
            ],
            -flow_into => {
                2 => [ 'part_multiply' ],   # will create a fan of jobs
                1 => [ 'add_together'  ],   # will create a funnel job to wait for the fan to complete and add the results
            },
        },

        {   -logic_name    => 'part_multiply',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply',
            -parameters    => {},
            -input_ids     => [
                # (jobs for this analysis will be flown_into via branch-2 from 'sema_start' jobs above)
            ],
            -flow_into => {
                1 => [ 'mysql:////intermediate_result' ],
            },

        },
        
        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether',
            -parameters => {},
            -input_ids => [
                # (jobs for this analysis will be flown_into via branch-1 from 'sema_start' jobs above)
            ],
            # jobs in this analyses are semaphored, so no need to '-wait_for'
            -flow_into => {
                1 => [ 'mysql:////final_result' ],
            },
        },
    ];
}

1;

