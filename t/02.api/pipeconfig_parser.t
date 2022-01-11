#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

use Test::Exception;
use Test::More;
use Test::Warn;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils::PCL;

my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new();
my ($analysis) = $pipeline->add_new_or_update('Analysis', logic_name => 'first'); 

subtest 'dataflow', sub {

    warnings_are {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, [ 'first' ]);
    } [], 'no warnings if the analysis exists';

    warning_like {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, [ 'oops_i_am_missing' ]);
    } qr/WARNING: Could not find a local analysis named 'oops_i_am_missing' \Q(dataflow from analysis 'first')/, 'warning about missing analysis';

    throws_ok {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, [ '<oops_i_am_missing>' ]);
    } qr/Could not parse the URL '<oops_i_am_missing>' .dataflow from analysis/, 'invalid URL';

    warnings_are {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, [ '?logic_name=oops_i_am_missing' ]);
    } [], 'no warnings when using an analysis URL, even if it does not exist';

    # Accumulators are accepted
    warnings_are {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis, [ '?accu_name=oops_i_am_missing' ]);
    } [], 'accu targets are accepted';
};

subtest 'wait_for', sub {

    warnings_are {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, [ 'first' ]);
    } [], 'no warnings if the analysis exists';

    warning_like {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, [ 'oops_i_am_missing' ]);
    } qr/WARNING: Could not find a local analysis 'oops_i_am_missing' to create a control rule \Q(in 'first')/, 'warning about missing analysis';

    throws_ok {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, [ '<oops_i_am_missing>' ]);
    } qr/Could not parse the URL '<oops_i_am_missing>' to create a control rule/, 'invalid URL';

    warnings_are {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, [ '?logic_name=oops_i_am_missing' ]);
    } [], 'no warnings when using an analysis URL, even if it does not exist';

    throws_ok {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_wait_for($pipeline, $analysis, [ '?accu_name=oops_i_am_missing' ]);
    } qr/ERROR: The URL '.*' does not refer to an Analysis/, 'accu targets are not accepted';
};

done_testing();

