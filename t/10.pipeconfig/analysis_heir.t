#!/usr/bin/env perl

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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
use Capture::Tiny 'capture_stderr';

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker get_test_url_or_die);

my $expected_error_pattern = qq{WARNING: Could not find a local analysis named 'oops_i_am_missing' \Q(dataflow from analysis 'first')};

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

my $init_stderr = capture_stderr {
    local @INC = @INC;
    push @INC, $ENV{'EHIVE_ROOT_DIR'}.'/t/10.pipeconfig/';
    init_pipeline(
        'TestPipeConfig::MissingAnalysis_conf',
        $pipeline_url,
    );
};

like($init_stderr, qr/$expected_error_pattern/, 'init_pipeline generates missing analysis warning');

my $gc_init_stderr = capture_stderr {
    init_pipeline(
        'Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf',
        $pipeline_url,
    );
};

#unlike($gc_init_stderr, qr/WARNING/, 'no warning from pipeline without missing analysis');
# Hack for dealing with WARNING: MYSQL_OPT_RECONNECT unexpected warning
if ($gc_init_stderr ~= /WARNING/ && !$gc_init_stderr ~= /WARNING:\s+MYSQL_OPT_RECONNECT/) {
    fail('no warning from pipeline without missing analysis');
}

done_testing();

