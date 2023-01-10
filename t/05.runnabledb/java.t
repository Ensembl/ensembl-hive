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

use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

use Test::More;

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

SKIP: {
    skip "mvn not installed", 1 unless (`mvn -version 2>/dev/null`);

plan tests => 1;

standaloneJob(
    'org.ensembl.hive.TestRunnable',
    {
        'alpha' => 2,
    },
    [
        [
            'WARNING',
            'Fetch the world !',
            'INFO',
        ], [
            'WARNING',
            'Run the world !',
            'INFO',
        ], [
            'WARNING',
            'Write to the world !',
            'INFO',
        ], [
            'DATAFLOW',
            [{
                'gamma' => 80,
            }],
            2
        ]
    ],
    {
        'language'  => 'java',
    },
);

} # /SKIP

done_testing();

