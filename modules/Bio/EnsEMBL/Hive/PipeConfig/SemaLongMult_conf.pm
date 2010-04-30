## Configuration file for the *semaphored* long multiplication pipeline example

package Bio::EnsEMBL::Hive::PipeConfig::SemaLongMult_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_db' => {
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -dbname => $ENV{USER}.'_sema_long_mult_pipeline',
        },

        'pipeline_name' => 'slmult',
    };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive table creation

            # additional tables needed for long multiplication pipeline's operation:
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE intermediate_result (a_multiplier char(40) NOT NULL, digit tinyint NOT NULL, result char(41) NOT NULL, PRIMARY KEY (a_multiplier, digit))'",
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'CREATE TABLE final_result (a_multiplier char(40) NOT NULL, b_multiplier char(40) NOT NULL, result char(80) NOT NULL, PRIMARY KEY (a_multiplier, b_multiplier))'",
    ];
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'start',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::LongMult::SemaStart',
            -parameters => {},
            -input_ids => [
                { 'a_multiplier' => '9650516169', 'b_multiplier' => '327358788' },
                { 'a_multiplier' => '327358788', 'b_multiplier' => '9650516169' },
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
            # jobs in this analyses are semaphored, so no need to '-wait_for'
        },
    ];
}

1;

