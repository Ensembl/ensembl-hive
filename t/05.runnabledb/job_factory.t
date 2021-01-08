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

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob get_test_url_or_die make_new_db_from_sqls run_sql_on_db);

plan tests => 9;

# Need EHIVE_ROOT_DIR to be able to point at specific files
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );
my $input_job_factory = File::Basename::dirname( Cwd::realpath($0) ) . '/input_job_factory.sql';

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputlist'     => [10..12, 14..19, 21..29],
        'step'          => 4,
        'contiguous'    => 0,
        'column_names'  => [ 'foo' ],
    },
    [
        [
            'DATAFLOW',
            [
                {
                    "_range_start"      => 10,
                    "_range_end"        => 14,
                    "_range_count"      => 4,
                    "_range_list"       => [10,11,12,14],
                    "_start_foo"        => 10,
                    "_end_foo"          => 14,
                },
                {
                    "_range_start"      => 15,
                    "_range_end"        => 18,
                    "_range_count"      => 4,
                    "_range_list"       => [15,16,17,18],
                    "_start_foo"        => 15,
                    "_end_foo"          => 18,
                },
                {
                    "_range_start"      => 19,
                    "_range_end"        => 23,
                    "_range_count"      => 4,
                    "_range_list"       => [19,21,22,23],
                    "_start_foo"        => 19,
                    "_end_foo"          => 23,
                },
                {
                    "_range_start"      => 24,
                    "_range_end"        => 27,
                    "_range_count"      => 4,
                    "_range_list"       => [24,25,26,27],
                    "_start_foo"        => 24,
                    "_end_foo"          => 27,
                },
                {
                    "_range_start"      => 28,
                    "_range_end"        => 29,
                    "_range_count"      => 2,
                    "_range_list"       => [28,29],
                    "_start_foo"        => 28,
                    "_end_foo"          => 29,
                },
            ],
            2
        ]
    ]
);

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputlist'     => [10..12, 14..19, 21..29],
        'step'          => 4,
        'contiguous'    => 1,
        'column_names'  => [ 'foo' ],
    },
    [
        [
            'DATAFLOW',
            [
                {
                    "_range_start"      => 10,
                    "_range_end"        => 12,
                    "_range_count"      => 3,
                    "_range_list"       => [10,11,12],
                    "_start_foo"        => 10,
                    "_end_foo"          => 12,
                },
                {
                    "_range_start"      => 14,
                    "_range_end"        => 17,
                    "_range_count"      => 4,
                    "_range_list"       => [14,15,16,17],
                    "_start_foo"        => 14,
                    "_end_foo"          => 17,
                },
                {
                    "_range_start"      => 18,
                    "_range_end"        => 19,
                    "_range_count"      => 2,
                    "_range_list"       => [18,19],
                    "_start_foo"        => 18,
                    "_end_foo"          => 19,
                },
                {
                    "_range_start"      => 21,
                    "_range_end"        => 24,
                    "_range_count"      => 4,
                    "_range_list"       => [21,22,23,24],
                    "_start_foo"        => 21,
                    "_end_foo"          => 24,
                },
                {
                    "_range_start"      => 25,
                    "_range_end"        => 28,
                    "_range_count"      => 4,
                    "_range_list"       => [25,26,27,28],
                    "_start_foo"        => 25,
                    "_end_foo"          => 28,
                },
                {
                    "_range_start"      => 29,
                    "_range_end"        => 29,
                    "_range_count"      => 1,
                    "_range_list"       => [29],
                    "_start_foo"        => 29,
                    "_end_foo"          => 29,
                },
            ],
            2
        ]
    ]
);

srand 1;
standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputlist'     => [1..5],
        'randomize'     => 1,
        'column_names'  => [ 'foo' ],
    },
    [
        [
            'DATAFLOW',
            [
                # The order depends on the above-initialized seed
                { 'foo' => 4 },
                { 'foo' => 5 },
                { 'foo' => 3 },
                { 'foo' => 2 },
                { 'foo' => 1 },
            ],
            2
        ]
    ]
);

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputlist'     => [1..5],
    },
    [
        [
            'DATAFLOW',
            [
                { '_0' => 1, '_' => [ 1 ] },
                { '_0' => 2, '_' => [ 2 ] },
                { '_0' => 3, '_' => [ 3 ] },
                { '_0' => 4, '_' => [ 4 ] },
                { '_0' => 5, '_' => [ 5 ] },
            ],
            2
        ]
    ]
);


my $original = Cwd::getcwd;
chdir $ENV{EHIVE_ROOT_DIR}.'/sql';

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputcmd'      => 'find . -iname "patch_2012-09-*" | sort',
        'step'          => 2,
    },
    [
        [
            'DATAFLOW',
            [
                {
                    "_range_start"      => "./patch_2012-09-04.sql",
                    "_range_end"        => "./patch_2012-09-21.sql",
                    "_range_count"      => 2,
                    "_range_list"       => ["./patch_2012-09-04.sql", "./patch_2012-09-21.sql"],
                    "_start_0"          => "./patch_2012-09-04.sql",
                    "_end_0"            => "./patch_2012-09-21.sql",
                },
                {
                    "_range_start"      => "./patch_2012-09-24.sql",
                    "_range_end"        => "./patch_2012-09-25.sql",
                    "_range_count"      => 2,
                    "_range_list"       => ["./patch_2012-09-24.sql", "./patch_2012-09-25.sql"],
                    "_start_0"          => "./patch_2012-09-24.sql",
                    "_end_0"            => "./patch_2012-09-25.sql",
                },
            ],
            2
        ]
    ]
);

my $l1 = q{ALTER TABLE analysis_stats ADD COLUMN max_retry_count int(10) DEFAULT 3 NOT NULL AFTER done_job_count;};
my $l2 = q{ALTER TABLE analysis_stats ADD COLUMN failed_job_tolerance int(10) DEFAULT 0 NOT NULL AFTER max_retry_count;};

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputfile'     => $input_job_factory,
        'column_names'  => [ 'line' ],
    },
    # The files contains 3 lines but the last one is empty. JobFactory only
    # selects the non-empty lines
    [
        [
            'DATAFLOW',
            [
                { 'line' => $l1 },
                { 'line' => $l2 },
            ],
            2
        ]
    ]
);


my $test_url = get_test_url_or_die();
my ($k1, $v1) = ('one_key', 34);
my ($k2, $v2) = ('another_key', -5);
my $dbc = make_new_db_from_sqls(
    $test_url,
    [
        'CREATE TABLE params (param_key VARCHAR(15), param_value INT)',
        "INSERT INTO params VALUES ('$k1', $v1)",
        "INSERT INTO params VALUES ('$k2', $v2)"
    ],
    'Dummy database with a single table and two rows'
);

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
    {
        'inputquery'    => 'SELECT * FROM params',
        'db_conn'       => $test_url,
    },
    [
        [
            'DATAFLOW',
            [
                { 'param_key' => $k1, 'param_value' => $v1 },
                { 'param_key' => $k2, 'param_value' => $v2 },
            ],
            2
        ]
    ]
);
$dbc->disconnect_if_idle();
run_sql_on_db($test_url, 'DROP DATABASE');

done_testing();

chdir $original;

