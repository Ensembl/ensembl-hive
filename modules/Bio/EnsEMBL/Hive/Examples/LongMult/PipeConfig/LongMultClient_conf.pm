=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultClient_conf;

=head1 SYNOPSIS

       # initialize the "server" database first and note its URL - you will need it to initialize the "client" later:
    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultServer_conf -password <mypass>

       # initialize the "client" database by plugging the server's URL:
    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultClient_conf -password <mypass> -server_url $SERVER_HIVE_URL

        # optionally also seed it with your specific values:
    seed_pipeline.pl -url $CLIENT_HIVE_URL -logic_name take_b_apart -input_id '{ "a_multiplier" => "12345678", "b_multiplier" => "3359559666" }'

        # run the first analysis of the "Client" in order to seed the first jobs into the "Server" pipeline
    runWorker.pl -url $CLIENT_HIVE_URL

        # run the "Server" (it will exit when all its jobs are done)
    beekeeper.pl -url $SERVER_HIVE_URL -loop_until NO_WORK

        # run the "Client" (it will exit when all its jobs are done)
    beekeeper.pl -url $CLIENT_HIVE_URL -loop_until NO_WORK

=head1 DESCRIPTION

    This is the "Client" PipeConfig file of a special two-part version of the long multiplication example pipeline.
    Please make sure you FULLY understand how the LongMult_conf works before trying this one.

    We have split the original LongMult_conf into two parts, the "Client" and the "Server" that can be used to initialize
    two separate Hive pipeline databases.

    The "Client" kept all the original analyses and the 'final_result' table, but prefers to delegate some of the jobs on the "Server" side.
    So the "Server" has its own 'part_multiply' to do some of the multiplication work, and its own 'add_together' and the 'final_result'
    table to do some of the final additions.

    The link between the pipelines is established via the -server_url command line flag that is passed to the Client database.
    Thanks to the support of cross-database semaphores we no longer need to depend on static tables, and use cross-database accumulators
    for returning the data, whether from a local or a remote fan (in this example we have a mix).

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultClient_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow and INPUT_PLUS



=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates two pipeline-specific tables used by Runnables to communicate.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        $self->db_cmd('CREATE TABLE final_result (a_multiplier varchar(40) NOT NULL, b_multiplier varchar(40) NOT NULL, result varchar(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'),
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


sub pipeline_analyses {
    my ($self) = @_;
    return [
            # the factory:
        {   -logic_name => 'take_b_apart',
            -module     => 'Bio::EnsEMBL::Hive::Examples::LongMult::RunnableDB::DigitFactory',
            -meadow_type=> 'LOCAL',     # do not bother the farm with such a simple task (and get it done faster)
            -analysis_capacity  =>  2,  # use per-analysis limiter
            -input_ids => [
                { 'a_multiplier' => '9650156169', 'b_multiplier' => '327358788' },
                { 'a_multiplier' => '327358788', 'b_multiplier' => '9650156169' },
            ],
            -flow_into => {
                '2->A' => WHEN(
                                    # some fan jobs are outsourced to the "Server":
                                '#digit#>5' => { $self->o('server_url').'?logic_name=part_multiply'
                                                     => INPUT_PLUS( { 'digit' => '#digit#', 'take_time' => '#take_time#' } ),
                                               },

                                    # some are run locally:
                                '#digit#>1 && #digit#<=5' => { 'part_multiply' => INPUT_PLUS() },
                          ),

                'A->1' => WHEN (
                                    # some funnels are outsourced to the "Server":
                                '#a_multiplier#>=#b_multiplier#'    =>  $self->o('server_url').'?logic_name=add_together',

                                    # and some are run locally:
                                ELSE                                    'add_together',
                        ),
            },
        },

            # the "Client"-side fan analysis (performs multiplication by lower digits)
        {   -logic_name => 'part_multiply',
            -module     => 'Bio::EnsEMBL::Hive::Examples::LongMult::RunnableDB::PartMultiply',
            -analysis_capacity  =>  4,  # use per-analysis limiter
            -flow_into => {
                1 => '?accu_name=partial_product&accu_address={digit}&accu_input_variable=product',
            },
        },

            # the "Client"-side funnel:
        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::Examples::LongMult::RunnableDB::AddTogether',
            -flow_into => {
                1 => '?table_name=final_result',
            },
        },
    ];
}

1;

