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

use Test::Exception;
use Test::More;
use Data::Dumper;
use Capture::Tiny 'capture_stderr';

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker db_cmd get_test_url_or_die);

my $expected_error_pattern = qq{WARNING: Could not find a local analysis named 'oops_i_am_missing' \Q(dataflow from analysis 'first')};

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

my $init_stderr = capture_stderr {
    local $ENV{'PERL5LIB'} = $ENV{'EHIVE_ROOT_DIR'}.'/t/10.pipeconfig/::'.$ENV{PERL5LIB};
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

unlike($gc_init_stderr, qr/WARNING/, 'no warning from pipeline without missing analysis');

subtest 'Drop on error' => sub {

    # To ensure we start with the database being absent
    db_cmd($pipeline_url, [-sql => 'DROP DATABASE IF EXISTS']);

    # Will fail because PERL5LIB hasn't been updated to include the local directory
    init_pipeline('TestPipeConfig::MissingAnalysis_conf', $pipeline_url, [], [],
        {
            'expect_failure' => qr/Can't locate TestPipeConfig\/MissingAnalysis_conf.pm in \@INC/,
        }
    );

    my $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-url => $pipeline_url);
    if ($dbc->driver eq 'sqlite') {
        ok(!-e $dbc->dbname, $dbc->dbname . q{ doesn't exist})
    } else {
        throws_ok {
            $dbc->connect;
        } qr/Could not connect to database.*DBI connect\(.*\) failed/s, q{The database doesn't exist};
    }

};

done_testing();

