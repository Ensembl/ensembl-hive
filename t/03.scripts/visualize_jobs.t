#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2017] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Getopt::Long qw(:config pass_through);
use File::Temp qw/tempfile/;                # temporary local file to compare to the expected diagram
use Test::File::Contents;                   # import file_contents_eq_or_diff()
use Test::More;

use Bio::EnsEMBL::Hive::Utils::Config;      # for Bio::EnsEMBL::Hive::Utils::Config->default_system_config
use Bio::EnsEMBL::Hive::Utils::Test qw(runWorker beekeeper run_sql_on_db get_test_url_or_die);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my ($generate_files, $generate_format) = (0, 'dot');

GetOptions(         # Example: "visualize_jobs.t -generate -format png" would yield a visualized walk-through
    'generate!' => \$generate_files,
    'format=s'  => \$generate_format,
);

my $vj_url  = get_test_url_or_die(-tag => 'vj', -no_user_prefix => 1);


my $ref_output_location = $ENV{'EHIVE_ROOT_DIR'}.'/t/03.scripts/visualize_jobs';

# A temporary file to store the output of generate_graph.pl
my ($fh, $generated_diagram_filename) = tempfile(UNLINK => 1);
close($fh);

sub test_command {
    my $cmd_array = shift;
    ok(!system(@$cmd_array), 'Can run '.join(' ', @$cmd_array));
}


my $conf_2_plan = {
    'LongMult::PipeConfig::LongMult_conf'   => [
            [ ],                # an empty list effectively skips running a worker (which is useful in the beginning)
            [  1,       [ qw(-analyses_pattern add_together -sync) ] ],
            [  2,       [ qw(-sync) ] ],
            [  4 ],
            [ 10, 11 ],
            [  5,  6 ],
            [  8, 12,   [ qw(-analyses_pattern add_together -sync) ] ],
            [  9,       [ qw(-analyses_pattern add_together -sync) ] ],
            [  7,       [ qw(-sync) ] ],
            [  3,       [ qw(-sync) ] ],
    ],
};

foreach my $conf (keys %$conf_2_plan) {
    subtest $conf, sub {
        my $module_name     = 'Bio::EnsEMBL::Hive::Examples::'.$conf;
        my $jobs_in_order   = $conf_2_plan->{$conf};

        my @init_pipeline_args = (  $ENV{'EHIVE_ROOT_DIR'}.'/scripts/init_pipeline.pl',
                                    $module_name,
                                    -pipeline_url => $vj_url,
                                    -hive_force_init => 1,
                                    -tweak => 'pipeline.param[take_time]=0'
                                 );
        test_command(\@init_pipeline_args);

        my $pipeline_name   = Bio::EnsEMBL::Hive::HivePipeline->new( -url => $vj_url )->hive_pipeline_name;

        my $ref_directory   = "${ref_output_location}/${pipeline_name}";
        if($generate_files) {
            system('mkdir', '-p', $ref_directory);
        }

        foreach my $step_number (0..@$jobs_in_order-1) {
            
            foreach my $job_id_or_bk_args ( @{ $jobs_in_order->[$step_number] } ) {
                if( ref($job_id_or_bk_args) ) {
                    beekeeper($vj_url, $job_id_or_bk_args );
                } else {
                    runWorker($vj_url, [ -job_id => $job_id_or_bk_args ] );
                }
            }

            my @visualize_jobs_args = ( $ENV{'EHIVE_ROOT_DIR'}.'/scripts/visualize_jobs.pl',
                                        # -config_file => Bio::EnsEMBL::Hive::Utils::Config->default_system_config,     ## FIXME: not supported yet
                                        -url => $vj_url,
                                        -accu_values,
                                        ($generate_format eq 'dot')
                                            ? (
                                                -output => '/dev/null',
                                                -format => 'canon',
                                                -dot_input => $generated_diagram_filename,
                                            ) : (
                                                -format => $generate_format,
                                                -output => $generated_diagram_filename,
                                            )
                                    );
            test_command(\@visualize_jobs_args);

            my $ref_filename    = sprintf("%s/%s_jobs_%02d.%s", $ref_directory, $pipeline_name, $step_number+1, $generate_format);

            if($generate_files) {
                system('cp', '-f', $generated_diagram_filename, $ref_filename);
            } else {
                files_eq_or_diff($generated_diagram_filename, $ref_filename);
            }
        }
    }
}

run_sql_on_db($vj_url, 'DROP DATABASE');

done_testing();

