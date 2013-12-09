=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::LongMultSt_conf;

=head1 SYNOPSIS

       # initialize the database and build the graph in it (it will also print the value of EHIVE_URL) :
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass>

        # optionally also seed it with your specific values:
    seed_pipeline.pl -url $EHIVE_URL -logic_name take_b_apart -input_id '{ "a_multiplier" => "12345678", "b_multiplier" => "3359559666" }'

        # run the pipeline:
    beekeeper.pl -url $EHIVE_URL -loop

=head1 DESCRIPTION

    This is a special version of LongMult_conf with hive_use_param_stack mode switched on.

    This is the PipeConfig file for the long multiplication pipeline example.
    The main point of this pipeline is to provide an example of how to write Hive Runnables and link them together into a pipeline.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf module to understand the interface implemented here.

    The setting. Let's assume we are given two loooooong numbers to multiply. Reeeeally long.
    Soooo long that they do not fit into registers of the CPU and should be multiplied digit-by-digit.
    For the purposes of this example we also assume this task is very computationally intensive and has to be done in parallel.

    The long multiplication pipeline consists of three "analyses" (types of tasks):
        'take_b_apart', 'part_multiply' and 'add_together' that we use to examplify various features of the Hive.

        * A 'take_b_apart' job takes in two string parameters, 'a_multiplier' and 'b_multiplier',
          takes the second one apart into digits, finds what _different_ digits are there,
          creates several jobs of the 'part_multiply' analysis and one job of 'add_together' analysis.

        * A 'part_multiply' job takes in 'a_multiplier' and 'digit', multiplies them and accumulates the result in 'partial_product' accumulator.

        * An 'add_together' job waits for the first two analyses to complete,
          takes in 'a_multiplier', 'b_multiplier' and 'partial_product' hash and produces the final result in 'final_result' table.

    Please see the implementation details in Runnable modules themselves.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::LongMultSt_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates two pipeline-specific tables used by Runnables to communicate.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        $self->db_cmd('CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'),
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

        'take_time'     => 1,
    };
}


sub hive_meta_table {
    my ($self) = @_;
    return {
        %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class

        'hive_use_param_stack'  => 1,           # switch on the new param_stack mechanism
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:
                    * 'take_b_apart' that is auto-seeded with a pair of jobs (to check the commutativity of multiplication).
                      Each job will dataflow (create more jobs) via branch #2 into 'part_multiply' and via branch #1 into 'add_together'.

                    * 'part_multiply' with jobs fed from take_b_apart#2.
                        It multiplies input parameters 'a_multiplier' and 'digit' and dataflows 'partial_product' parameter into branch #1.

                    * 'add_together' with jobs fed from take_b_apart#1.
                        It adds together results of partial multiplication computed by 'part_multiply'.
                        These results are accumulated in 'partial_product' hash.
                        Until the hash is complete the corresponding 'add_together' job is blocked by a semaphore.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'take_b_apart',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::DigitFactory',
            -meadow_type=> 'LOCAL',     # do not bother the farm with such a simple task (and get it done faster)
            -analysis_capacity  =>  2,  # use per-analysis limiter
            -input_ids => [
                { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788' },
                { 'a_multiplier' => '327358788', 'b_multiplier' => '9650156169' },
            ],
            -flow_into => {
                '2->A' => [ 'part_multiply' ],   # will create a semaphored fan of jobs; will use param_stack mechanism to pass parameters around
                'A->1' => [ 'add_together'  ],   # will create a semaphored funnel job to wait for the fan to complete and add the results
            },
        },

        {   -logic_name => 'part_multiply',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply',
            -analysis_capacity  =>  4,  # use per-analysis limiter
            -flow_into => {
                1 => [ ':////accu?partial_product={digit}' ],
            },
        },
        
        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether',
#           -analysis_capacity  =>  0,  # this is a way to temporarily block a given analysis
            -flow_into => {
                1 => [ ':////final_result', 'last' ],
            },
        },

        {   -logic_name => 'last',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        }
    ];
}

1;

