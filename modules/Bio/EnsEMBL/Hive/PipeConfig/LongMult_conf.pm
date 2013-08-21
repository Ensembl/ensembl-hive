
=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf;

=head1 SYNOPSIS

   # Example 1: specifying only the mandatory option (numbers to be multiplied are taken from defaults)
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass>

   # Example 2: specifying the mandatory options as well as overriding the default numbers to be multiplied:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass> -first_mult 2344556 -second_mult 777666555

   # Example 3: do not re-create the database, just load another multiplicaton task into an existing one:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -job_topup -password <mypass> -first_mult 1111222233334444 -second_mult 38578377835


=head1 DESCRIPTION

    This is the PipeConfig file for the long multiplication pipeline example.
    The main point of this pipeline is to provide an example of how to write Hive Runnables and link them together into a pipeline.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf module to understand the interface implemented here.


    The setting. Let's assume we are given two loooooong numbers to multiply. Reeeeally long.
    So long that they do not fit into registers of the CPU and should be multiplied digit-by-digit.
    For the purposes of this example we also assume this task is very computationally intensive and has to be done in parallel.

    The long multiplication pipeline consists of three "analyses" (types of tasks):  'take_b_apart', 'part_multiply' and 'add_together'
    that we will be using to examplify various features of the Hive.

        * A 'take_b_apart' job takes in two string parameters, 'a_multiplier' and 'b_multiplier',
          takes the second one apart into digits, finds what _different_ digits are there,
          creates several jobs of the 'part_multiply' analysis and one job of 'add_together' analysis.

        * A 'part_multiply' job takes in 'a_multiplier' and 'digit', multiplies them and accumulates the result in 'partial_product' accumulator.

        * An 'add_together' job waits for the first two analyses to complete,
          takes in 'a_multiplier', 'b_multiplier' and 'partial_product' hash and produces the final result in 'final_result' table.

    Please see the implementation details in Runnable modules themselves.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf;

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
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        'pipeline_name' => 'long_mult',                     # name used by the beekeeper to prefix job names on the farm

        'first_mult'    => '9650156169',                    # the actual numbers to be multiplied can also be specified from the command line
        'second_mult'   =>  '327358788',

        'take_time'     => 1,                               # how much time (in seconds) should each job take -- to slow things down
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
        'db_conn.pl -url '.$self->dbconn_2_url('pipeline_db').' -sql '
            ."'CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'",
    ];
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure now (will be stringified and de-stringified automagically).
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'take_time' => $self->o('take_time'),
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:

                    * 'take_b_apart' with two jobs (multiply 'first_mult' by 'second_mult' and vice versa - to check the commutativity of multiplivation).
                      Each job will dataflow (create more jobs) via branch #2 into 'part_multiply' and via branch #1 into 'add_together'.

                    * 'part_multiply' initially without jobs (they will flow from 'take_b_apart')

                    * 'add_together' initially without jobs (they will flow from 'take_b_apart').
                       All 'add_together' jobs will wait for completion of 'part_multiply' jobs before their own execution (to ensure all data is available).

    There are two control modes in this pipeline:
        A. The default mode is to use the '2' and '1' dataflow rules from 'take_b_apart' analysis and a -wait_for rule in 'add_together' analysis for analysis-wide synchronization.
        B. The semaphored mode is to use '2->A' and 'A->1' semaphored dataflow rules from 'take_b_apart' instead, and comment out the analysis-wide -wait_for rule, relying on semaphores.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'take_b_apart',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::DigitFactory',
            -meadow_type=> 'LOCAL',     # do not bother the farm with such a simple task (and get it done faster)
            -analysis_capacity  =>  2,  # use per-analysis limiter
            -input_ids => [
                { 'a_multiplier' => $self->o('first_mult'),  'b_multiplier' => $self->o('second_mult') },
                { 'a_multiplier' => $self->o('second_mult'), 'b_multiplier' => $self->o('first_mult')  },
            ],
            -flow_into => {
                '2->A' => { 'part_multiply' => { 'a_multiplier' => '#a_multiplier#', 'digit' => '#digit#' } },   # will create a semaphored fan of jobs; will use a template to top-up the hashes
                'A->1' => [ 'add_together' ],   # will create a semaphored funnel job to wait for the fan to complete and add the results
            },
        },

        {   -logic_name    => 'part_multiply',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply',
            -analysis_capacity  =>  4,  # use per-analysis limiter
            -flow_into => {
                1 => { ':////accu?partial_product={digit}' => { 'a_multiplier' => '#a_multiplier#', 'digit' => '#digit#', 'partial_product' => '#partial_product#' } },
            },
        },
        
        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether',
#           -analysis_capacity  =>  0,  # this is a way to temporarily block a given analysis
            -flow_into => {
                1 => { ':////final_result' => { 'a_multiplier' => '#a_multiplier#', 'b_multiplier' => '#b_multiplier#', 'result' => '#result#' } },
            },
        },
    ];
}

1;

