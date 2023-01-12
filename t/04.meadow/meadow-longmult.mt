#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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

use Test::More;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline beekeeper get_test_urls safe_drop_database);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
BAIL_OUT('$EHIVE_ROOT_DIR must be defined !') unless $ENV{'EHIVE_ROOT_DIR'};

my $testing_meadow_type = $ENV{EHIVE_MEADOW_TO_TEST} || die "The environment variable \$EHIVE_MEADOW_TO_TEST is not set\n";

my @pipeline_urls = @{get_test_urls()};
my @pipeline_cfgs = qw(LongMult_conf);

foreach my $long_mult_version ( @pipeline_cfgs ) {

    note("\nInitializing the $long_mult_version pipeline ...\n\n");

    foreach my $pipeline_url (@pipeline_urls) {
            # override the 'take_time' PipelineWideParameter in the loaded HivePipeline object to make the internal test Worker run quicker:
        init_pipeline(
            ($long_mult_version =~ /::/ ? $long_mult_version : 'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::'.$long_mult_version),
            $pipeline_url,
            [],
            ['pipeline.param[take_time]=0', 'analysis[take_b_apart].meadow_type=undef', 'analysis[take_b_apart].analysis_capacity=1'],
        );

        my $hive_dba    = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

        beekeeper($pipeline_url, [-sleep => 0.2, '-loop']);
        is(scalar(@{$hive_dba->get_AnalysisJobAdaptor->fetch_all("status != 'DONE'")}), 0, 'All the jobs could be run');
        is(scalar(@{$hive_dba->get_WorkerAdaptor->fetch_all("meadow_type != '$testing_meadow_type'")}), 0, "All the workers were run under the $testing_meadow_type meadow");

        my $final_result_nta = $hive_dba->get_NakedTableAdaptor( 'table_name' => 'final_result' );
        my $final_results = $final_result_nta->fetch_all();

        is(scalar(@$final_results), 2, 'There are exactly 2 final_results');
        foreach ( @$final_results ) {
            ok( $_->{'a_multiplier'}*$_->{'b_multiplier'} eq $_->{'result'},
                sprintf("%s*%s=%s", $_->{'a_multiplier'}, $_->{'b_multiplier'}, $_->{'result'}) );
        }

        safe_drop_database( $hive_dba );
    }
}

done_testing();

