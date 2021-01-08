#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

use Cwd;
use File::Basename;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils ('find_submodules');
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $dir = tempdir CLEANUP => 1;
my $original = Cwd::getcwd;
chdir $dir;

my $all_longmult_configs = find_submodules 'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig';

my $ehive_test_pipeline_urls = $ENV{'EHIVE_TEST_PIPELINE_URLS'} || 'sqlite:///ehive_test_pipeline_db';
my $ehive_test_pipeconfigs   = $ENV{'EHIVE_TEST_PIPECONFIGS'} || join(' ', @$all_longmult_configs);

my @pipeline_urls = split( /[\s,]+/, $ehive_test_pipeline_urls ) ;
my @pipeline_cfgs = split( /[\s,]+/, $ehive_test_pipeconfigs ) ;

foreach my $long_mult_version ( @pipeline_cfgs ) {

    # These have to be tested in a special way. See client_server.t
    next if $long_mult_version =~ /Server/;
    next if $long_mult_version =~ /Client/;

warn "\nInitializing the $long_mult_version pipeline ...\n\n";

    foreach my $pipeline_url (@pipeline_urls) {
            # override the 'take_time' PipelineWideParameter in the loaded HivePipeline object to make the internal test Worker run quicker:
        my $url         = init_pipeline(
                            ($long_mult_version =~ /::/ ? $long_mult_version : 'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::'.$long_mult_version),
                            [-pipeline_url => $pipeline_url, -hive_force_init => 1],
                            ['pipeline.param[take_time]=0'],
                        );

        my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                        => $url,
            -disconnect_when_inactive   => 1,
        );

        # First run a single worker in this process
        runWorker($pipeline, { can_respecialize => 1 });

        my $hive_dba    = $pipeline->hive_dba;
        my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
        is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');

        # Let's now try the combination of end-user scripts: seed_pipeline + beekeeper
        {
            my @seed_pipeline_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/seed_pipeline.pl', -url => $hive_dba->dbc->url, -logic_name => 'take_b_apart', -input_id => '{"a_multiplier" => 2222222222, "b_multiplier" => 3434343434}');
            my @beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $hive_dba->dbc->url, -sleep => 0.02, '-loop', '-local');

            system(@seed_pipeline_cmd);
            ok(!$?, 'seed_pipeline exited with the return code 0');
            is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 1, 'There are new jobs to run');

            system(@beekeeper_cmd);
            ok(!$?, 'beekeeper exited with the return code 0');
            is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');
        }

        my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
        my $final_results = $final_result_nta->fetch_all();

        is(scalar(@$final_results), 3, 'There are exactly 3 final_results');
        foreach ( @$final_results ) {
            ok( $_->{'a_multiplier'}*$_->{'b_multiplier'} eq $_->{'result'},
                sprintf("%s*%s=%s", $_->{'a_multiplier'}, $_->{'b_multiplier'}, $_->{'result'}) );
        }

        system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );
    }
}

done_testing();

chdir $original;

