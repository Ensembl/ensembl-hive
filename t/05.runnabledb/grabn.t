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

use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

my @input_id_list = map { {'param' => $_} } 1..10;

# 1. Standard cases (incl. exhaustion but within boundaries)

foreach my $x ([1,0], [0,1], [1,1], [2,0], [0,2], [2,2], [0,9], [9,0], [4,5], [0,10], [10,0], [5,5]) {
    my ($l, $r) = @$x;
    my $exhausted = ($l+$r) == 10 ? 1 : '';

    standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
        {
            'input_id_list' => \@input_id_list,
            'grab_n_left'   => $l,
            'grab_n_right'  => $r,
        },
        [
            [
                'DATAFLOW',
                [ @input_id_list[0..($l-1)], @input_id_list[(9-$r+1)..9] ],
                2,
            ],
            [
                'DATAFLOW',
                { '_list_exhausted' => $exhausted, 'input_id_list' => [@input_id_list[$l..(9-$r)]] },
                1,
            ],
        ],
    );


}


# 2. Edge cases

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 0,
        'grab_n_right'  => 0,
    },
    [
        [
            'DATAFLOW',
            { '_list_exhausted' => '', 'input_id_list' => \@input_id_list },
            1,
        ],
    ],
);

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 11,
        'grab_n_right'  => 0,
    },
    [
        [
            'DATAFLOW',
            \@input_id_list,
            2,
        ],
        [
            'DATAFLOW',
            { '_list_exhausted' => 1, 'input_id_list' => [] },
            1,
        ],
    ],
);

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 0,
        'grab_n_right'  => 11,
    },
    [
        [
            'DATAFLOW',
            \@input_id_list,
            2,
        ],
        [
            'DATAFLOW',
            { '_list_exhausted' => 1, 'input_id_list' => [] },
            1,
        ],
    ],
);

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 5,
        'grab_n_right'  => 10,
    },
    [
        [
            'DATAFLOW',
            \@input_id_list,
            2,
        ],
        [
            'DATAFLOW',
            { '_list_exhausted' => 1, 'input_id_list' => [] },
            1,
        ],
    ],
);

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 10,
        'grab_n_right'  => 5,
    },
    [
        [
            'DATAFLOW',
            \@input_id_list,
            2,
        ],
        [
            'DATAFLOW',
            { '_list_exhausted' => 1, 'input_id_list' => [] },
            1,
        ],
    ],
);


# 3. Unallowed parameters

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => -1,
        'grab_n_right'  => 0,
    },
    [
        [
            'WARNING',
            "Negative values are not allowed for 'grab_n_left'\n",
            'WORKER_ERROR',
        ],
    ],
    { 'expect_failure' => 1 },
);

standaloneJob('Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN',
    {
        'input_id_list' => \@input_id_list,
        'grab_n_left'   => 0,
        'grab_n_right'  => -1,
    },
    [
        [
            'WARNING',
            "Negative values are not allowed for 'grab_n_right'\n",
            'WORKER_ERROR',
        ],
    ],
    { 'expect_failure' => 1 },
);


done_testing();
