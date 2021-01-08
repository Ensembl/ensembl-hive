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
use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

# Fasta file for calculating %GC
my $inputfile = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ).'/input_fasta.fa';

my $dir = tempdir CLEANUP => 1;
my $original = Cwd::getcwd;
chdir $dir;

my $ehive_test_pipeline_urls = $ENV{'EHIVE_TEST_PIPELINE_URLS'} || 'sqlite:///ehive_test_pipeline_db';
my $ehive_test_pipeconfigs   = $ENV{'EHIVE_TEST_PIPECONFIGS'} || 'GCPct_conf';

my @pipeline_urls = split( /[\s,]+/, $ehive_test_pipeline_urls ) ;
my @pipeline_cfgs = split( /[\s,]+/, $ehive_test_pipeconfigs ) ;

foreach my $gcpct_version ( @pipeline_cfgs ) {

warn "\nInitializing the $gcpct_version pipeline ...\n\n";

    foreach my $pipeline_url (@pipeline_urls) {
            # override the 'take_time' PipelineWideParameter in the loaded HivePipeline object to make the internal test Worker run quicker:
        my $url         = init_pipeline(
                            'Bio::EnsEMBL::Hive::Examples::GC::PipeConfig::'.$gcpct_version,
                            [ -pipeline_url => $pipeline_url, -hive_force_init => 1 ],
                            [   'pipeline.param[take_time]=0',                              # tweak a pipeline-wide parameter
                                'analysis[chunk_sequences].param[inputfile]='.$inputfile,   # tweak an analysis-wide parameter
                            ],
                        );

        my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                        => $url,
            -disconnect_when_inactive   => 1,
        );

        # First run a single worker in this process
        runWorker($pipeline, { can_respecialize => 1 });

        my $hive_dba    = $pipeline->hive_dba;
        my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
        is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the runWorker jobs could be run');

        # Let's now try the combination of end-user scripts: seed_pipeline + beekeeper
        {
            my @beekeeper_cmd = ($ENV{'EHIVE_ROOT_DIR'}.'/scripts/beekeeper.pl', -url => $hive_dba->dbc->url, -sleep => 0.02, '-loop', '-local');

            system(@beekeeper_cmd);
            ok(!$?, 'beekeeper exited with the return code 0');
            is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');
        }

        my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
        my $final_results = $final_result_nta->fetch_all();

        is(scalar(@$final_results), 1, 'There is exactly 1 final_results');
        my $expected_result = '0.4875';
        foreach ( @$final_results ) {
            my $result_as_str = sprintf("%.4f", $_->{'result'});
            is($expected_result, $result_as_str, 'Got the correct result');
        }

        system( @{ $hive_dba->dbc->to_cmd(undef, undef, undef, 'DROP DATABASE') } );
    }
}

done_testing();

chdir $original;

