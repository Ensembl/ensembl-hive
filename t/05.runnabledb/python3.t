# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

plan tests => 1;

standaloneJob(
    'TestRunnable',
    {
        'alpha' => 2,
    },
    [
        [
            'WARNING',
            'Fetch the world !',
            JSON::false,
        ], [
            'WARNING',
            'Run the world !',
            JSON::false,
        ], [
            'WARNING',
            'Write to the world !',
            JSON::false,
        ], [
            'DATAFLOW',
            {
                'gamma' => 80,
            },
            2
        ]
    ],
    {
        'language'  => 'python3',
    },
);

done_testing();

