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

use Test::More;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils qw(stringify);
use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'echo hello world >&2',
});

# This is expected to complete succesfully since the return status of a
# pipe is the last command's
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'exit 1 | exit 0',
});

# With "use_bash_pipefail" enabled, we can catch the error with a dataflow
my $input_hash = {
    'cmd'                       => 'exit 1 | exit 0',
    'use_bash_pipefail'         => 1,
    'return_codes_2_branches'   => { 1 => 4 },
};
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    $input_hash, [
        [
            'DATAFLOW',
            stringify($input_hash),
            4,
        ], [
            'WARNING',
            "The command exited with code 1, which is mapped to a dataflow on branch #4.\n",
            0,
        ],
    ],
);


done_testing();
