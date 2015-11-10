=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::LongMultClient_conf;

=head1 SYNOPSIS

       # initialize the "server" database first and note its URL - you will need it to initialize the "client" later:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMultServer_conf -password <mypass>

       # initialize the "client" database by plugging the server's URL:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMultClient_conf -password <mypass> -server_url $SERVER_HIVE_URL

        # optionally also seed it with your specific values:
    seed_pipeline.pl -url $CLIENT_HIVE_URL -logic_name take_b_apart -input_id '{ "a_multiplier" => "12345678", "b_multiplier" => "3359559666" }'

        # run the "server" (it will have to be stopped manually when the "client" is done):
    beekeeper.pl -url $SERVER_HIVE_URL -keep_alive

        # run the "client" (it will exit by itself):
    beekeeper.pl -url $CLIENT_HIVE_URL -loop

=head1 DESCRIPTION

    This is the "client" PipeConfig file of a special two-part version of the long multiplication example pipeline.
    Please make sure you FULLY understand how the LongMult_conf works before trying this one.

    We have split the original LongMult_conf into two parts, the "client" and the "server" that can be used to initialize
    two separate Hive pipeline databases.

    The "client" kept 'take_apart' and 'add_together' analyses and the 'final_result' table, but the 'part_multpily' analysis
    has been outsourced into the "server" which also maintains its local 'intermediate_result' table.

    There are 3 links between the pipelines, all established from the "client" side (the "server" doesn't know about them) :
        1. The "client" seeds the "server" via a cross-database dataflow rule ('take_b_apart'#2 -> 'part_multiply)
        2. The "client" waits for the 'part_multiply' analysis to complete on the "server" via an analysis_ctrl_rule
        3. The "client" reads the data from the 'intermediate_result' table of the "server"

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


package Bio::EnsEMBL::Hive::PipeConfig::LongMultClient_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;           # Allow this particular config to use conditional dataflow


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
                    # A WHEN block is not a hash, so multiple occurences of each condition (including ELSE) is permitted.
                2 => WHEN(
                        '#digit#>1' =>  { $self->o('server_url').'/analysis?logic_name=part_multiply'
                                            => { 'a_multiplier' => '#a_multiplier#', 'digit' => '#digit#', 'take_time' => '#take_time#', 'foreign' => 1 },
                                        },
                ),
                1 => [ 'add_together' ],
            },
        },

        #
        # 'take_b_apart' seeds an externally looping "server" pipeline which will put results into its local 'intermediate_result' table and unblock 'add_together'
        #

        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether',
            -parameters => {
                'intermediate_table_url' => $self->o('server_url').'/intermediate_result',
            },
            -wait_for => [ $self->o('server_url').'/analysis?logic_name=part_multiply' ],
            -flow_into => {
                1 => [ ':////final_result' ],
            },
        },
    ];
}

1;

