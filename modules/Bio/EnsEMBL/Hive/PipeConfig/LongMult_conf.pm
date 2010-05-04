## Configuration file for the long multiplication pipeline example

package Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'long_mult',                     # name used by the beekeeper to prefix job names on the farm

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

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE intermediate_result (a_multiplier char(40) NOT NULL, digit tinyint NOT NULL, result char(41) NOT NULL, PRIMARY KEY (a_multiplier, digit))'",
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'",
    ];
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'start',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::Start',
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
                # (jobs for this analysis will be flown_into via branch-2 from 'start' jobs above)
            ],
        },
        
        {   -logic_name => 'add_together',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether',
            -parameters => {},
            -input_ids => [
                # (jobs for this analysis will be flown_into via branch-1 from 'start' jobs above)
            ],
            -wait_for => [ 'part_multiply' ],   # we can only start adding when all partial products have been computed
        },
    ];
}

1;

