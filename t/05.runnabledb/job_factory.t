#!/usr/bin/env perl

# Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

use JSON;
use Test::More;

use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

plan tests => 2;

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

done_testing();

