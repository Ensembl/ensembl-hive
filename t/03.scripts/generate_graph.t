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

use File::Temp qw/tempfile/;
use Test::File::Contents;
use Test::More;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::Config;
use Bio::EnsEMBL::Hive::Utils::Test qw(runWorker run_sql_on_db get_test_url_or_die);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $generate_files = 0;

my $server_url  = get_test_url_or_die(-tag => 'server', -no_user_prefix => 1);

# Most of the test scripts test init_pipeline() from Utils::Test but we
# also need to test the main scripts/init_pipeline.pl !
my @init_pipeline_args = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/init_pipeline.pl', 'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMultServer_conf', -pipeline_url => $server_url, -hive_force_init => 1, -tweak => 'pipeline.param[take_time]=0');
test_command(\@init_pipeline_args);

my $client_url  = get_test_url_or_die(-tag => 'client', -no_user_prefix => 1);

my $ref_output_location = $ENV{'EHIVE_ROOT_DIR'}.'/t/03.scripts/generate_graph/';

my @confs_to_test = qw(LongMult::PipeConfig::SmartLongMult_conf GC::PipeConfig::GCPct_conf LongMult::PipeConfig::LongMultWf_conf LongMult::PipeConfig::LongMultClient_conf);

# A temporary file to store the output of generate_graph.pl
my ($fh, $filename) = tempfile(UNLINK => 1);
close($fh);

sub test_command {
    my $cmd_array = shift;
    ok(!system(@$cmd_array), 'Can run '.join(' ', @$cmd_array));
}

my @common_diagram_args = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/generate_graph.pl', -config_file => Bio::EnsEMBL::Hive::Utils::Config->default_system_config );

foreach my $conf (@confs_to_test) {
  subtest $conf, sub {
    my $module_name = 'Bio::EnsEMBL::Hive::Examples::'.$conf;

    # Unicode-art (dbIDs are never shown, so we can use the PipeConfig directly)
    #$filename = $ref_output_location . $conf . '.txt';
    my @generate_graph_args = (@common_diagram_args, -pipeconfig => $module_name);
    push @generate_graph_args, (-server_url => $server_url) if $conf =~ /Client/;
    test_command( [join(' ', @generate_graph_args).' > '.$filename] );
    if($generate_files) {
        system('cp', $filename, $ref_output_location . $conf . '.txt');
    } else {
        files_eq_or_diff($filename, $ref_output_location . $conf . '.txt');
    }


    # Dot output on a PipeConfig (no dBIDs)
    #$filename = $ref_output_location . $conf . '.unstored.dot';
    @generate_graph_args = (@common_diagram_args, -pipeconfig => $module_name, -output => '/dev/null', -format => 'canon', -dot_input => $filename);
    push @generate_graph_args, (-server_url => $server_url) if $conf =~ /Client/;
    test_command(\@generate_graph_args);
    if($generate_files) {
        system('cp', $filename, $ref_output_location . $conf . '.unstored.dot');
    } else {
        files_eq_or_diff($filename, $ref_output_location . $conf . '.unstored.dot');
    }

    # Dot output on a database (no dBIDs)
    @init_pipeline_args = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/init_pipeline.pl', $module_name, -pipeline_url => $client_url, -hive_force_init => 1);
    push @init_pipeline_args, (-server_url => $server_url) if $conf =~ /Client/;
    test_command(\@init_pipeline_args);
    #my $filename = $ref_output_location . $conf . '.stored.dot';
    @generate_graph_args = (@common_diagram_args, -url => $client_url, -output => '/dev/null', -format => 'canon', -dot_input => $filename);
    test_command(\@generate_graph_args);
    if($generate_files) {
        system('cp', $filename, $ref_output_location . $conf . '.stored.dot');
    } else {
        files_eq_or_diff($filename, $ref_output_location . $conf . '.stored.dot');
    }
  }
}

run_sql_on_db($client_url, 'DROP DATABASE');
run_sql_on_db($server_url, 'DROP DATABASE');

done_testing();

