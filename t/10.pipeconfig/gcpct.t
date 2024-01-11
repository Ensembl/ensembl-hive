#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper get_test_url_or_die safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

SKIP: {
    eval { require Bio::SeqIO; };

    skip "Bioperl not installed", 2 if $@;

# Fasta file for calculating %GC
my $inputfile = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ).'/input_fasta.fa';

my $dir = tempdir CLEANUP => 1;

my $ehive_test_pipeconfigs   = $ENV{'EHIVE_TEST_PIPECONFIGS'} || 'GCPct_conf';

my @pipeline_cfgs = split( /[\s,]+/, $ehive_test_pipeconfigs ) ;
my $sleep_minutes = $ENV{'EHIVE_GCPCT_SLEEP'} || 0.02;

foreach my $gcpct_version ( @pipeline_cfgs ) {

        note("\nInitializing the $gcpct_version pipeline ...\n\n");

        my $pipeline_url = get_test_url_or_die();
            # override the 'take_time' PipelineWideParameter in the loaded HivePipeline object to make the internal test Worker run quicker:

        init_pipeline(
            'Bio::EnsEMBL::Hive::Examples::GC::PipeConfig::'.$gcpct_version,
            $pipeline_url,
            undef,
            [   'pipeline.param[take_time]=0',                                  # tweak a pipeline-wide parameter
                'analysis[chunk_sequences].param[output_dir]="'.$dir.'"',       # tweak an analysis-wide parameter
                'analysis[chunk_sequences].param[inputfile]="'.$inputfile.'"',  # tweak another analysis-wide parameter
            ],
        );

        # First run a single worker in this process
        runWorker($pipeline_url, [ '-can_respecialize' ]);

        my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );
        my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
        is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the runWorker jobs could be run');

        # Let's now try running a beekeeper
        my @beekeeper_options = (-sleep => $sleep_minutes, '-loop', '-local');
        beekeeper($hive_dba->dbc->url, \@beekeeper_options, 'beekeeper exited with the return code 0');
        is(scalar(@{$job_adaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');

        my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
        my $final_results = $final_result_nta->fetch_all();

        is(scalar(@$final_results), 1, 'There is exactly 1 final_results');
        my $expected_result = '0.4875';
        foreach ( @$final_results ) {
            my $result_as_str = sprintf("%.4f", $_->{'result'});
            is($expected_result, $result_as_str, 'Got the correct result');
        }

        # check beekeeper registration

        my $beekeeper_check_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'beekeeper' );
        my $beekeeper_entries = $beekeeper_check_nta->fetch_all();

        is(scalar(@$beekeeper_entries), 1, 'Exactly 1 beekeeper registered');
        my $beekeeper_row = $$beekeeper_entries[0];
        is($beekeeper_row->{'beekeeper_id'}, 1, 'beekeeper has a beekeeper_id of 1');
        is($beekeeper_row->{'cause_of_death'},  'NO_WORK', 'beekeeper finished with cause_of_death NO_WORK');
        my $stored_sleep_minutes_str = sprintf("%.3f", $beekeeper_row->{'sleep_minutes'});
        my $given_sleep_minutes_str = sprintf("%.3f", $sleep_minutes);
        is($stored_sleep_minutes_str, $given_sleep_minutes_str, 'beekeeper sleep_minutes recorded correctly');
        is($beekeeper_row->{'loop_limit'}, undef, 'no loop limit recorded');
        is($beekeeper_row->{'loop_until'}, 'ANALYSIS_FAILURE', 'beekeeper stop_when is LOOP_UNTIL');

        # substitute the password-obscured version of the url into the beeekeeper options string
        # for checking - this is how it should be stored in the beekeeper table
        my $obscured_url = $hive_dba->dbc->url('_EHIVE_HIDDEN_PASS');
        $obscured_url = "'$obscured_url'" if $hive_dba->dbc->password;
        my $beekeeper_options_string = join(' ', '-url', $obscured_url, @beekeeper_options);
        is($beekeeper_row->{'options'}, $beekeeper_options_string, 'beekeeper options stored correctly');

        safe_drop_database( $hive_dba );
}

}

done_testing();

