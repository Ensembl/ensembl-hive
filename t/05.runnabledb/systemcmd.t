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

use JSON;
use Test::More;
use Data::Dumper;
use File::Temp qw/tempfile/;

use Bio::EnsEMBL::Hive::Utils qw(stringify);
use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'echo hello world >&2',
});

# This is expected to fail
my $ctdne = 'command_that_does_not_exist';
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    { 'cmd' => $ctdne },
    [
        [
            'WARNING',
            qr/^Could not start '${ctdne}': Can't exec "${ctdne}": No such file or directory at/,
            'WORKER_ERROR'
        ],
    ],
    { 'expect_failure' => 1 },
);

# This is expected to fail too
my $ptdne = 'path_that_does_not_exist';
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    { 'cmd' => "ls $ptdne" },
    [
        [
            'WARNING',
            qr/'ls ${ptdne}' resulted in an error code=\d+\nstderr is: ls: .+: No such file or directory/,
            'WORKER_ERROR'
        ],
    ],
    { 'expect_failure' => 1 },
);

# Here we pretend we have run a Java program that failed because of memory
my $java_memory_error = 'This is Java speaking. Exception in thread "" java.lang.OutOfMemoryError: Java heap space at line 0';
my $input_hash = { 'cmd' => "echo '$java_memory_error' >&2 && exit 1" };
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    $input_hash,
    [
        [
            'DATAFLOW',
            undef,
            -1,
        ],
        [
            'WARNING',
            qr/Java heap space is out of memory. A job has been dataflown to the -1 branch/,
            'INFO'
        ],
    ],
    {
        'flow_into' => {
                '-1' => [ 'dummy' ],
            },
    },
);


# Here we pretend we have a command that takes to omuch time to complete
$input_hash = { 'cmd' => 'sleep 10', 'timeout' => 3 };
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    $input_hash,
    [
        [
            'DATAFLOW',
            undef,
            -2,
        ],
        [
            'WARNING',
            qr/The command was aborted because it exceeded the allowed runtime. Flowing to the -2 branch/,
            'INFO'
        ],
    ],
    {
        'flow_into' => {
                '-2' => [ 'dummy' ],
            },
    },
);


# This is expected to complete succesfully since the return status of a
# pipe is the last command's
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'exit 1 | exit 0',
});

# With "use_bash_pipefail" enabled, we can catch the error with a dataflow
$input_hash = {
    'cmd'                       => 'exit 1 | exit 0',
    'use_bash_pipefail'         => 1,
    'return_codes_2_branches'   => { 1 => 4 },
};
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    $input_hash, [
        [
            'DATAFLOW',
            undef,
            4,
        ], [
            'WARNING',
            "The command exited with code 1, which is mapped to a dataflow on branch #4.\n",
            'INFO',
        ],
    ],
);


# This is expected to complete succesfully since the return status of a
# sequence is the last command's
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd', {
        'cmd' => 'ls /_inexistent_ ; exit 0',
});

# With "use_bash_errexit" enabled, we can catch the error with a dataflow
$input_hash = {
    'cmd'                       => 'ls /_inexistent_; exit 0',
    'use_bash_errexit'          => 1,
    'return_codes_2_branches'   => {
                                    2 => 4,     # on Linux
                                    1 => 4      # on OSX
                                   },
};
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    $input_hash, [
        [
            'DATAFLOW',
            undef,
            4,
        ], [
            'WARNING',
            qr/The command exited with code \d, which is mapped to a dataflow on branch #4.\n/,
            'INFO',
        ],
    ],
);


my $json_formatter = JSON->new()->indent(0);
my $array_of_hashes = [{'key1' => 1}, {"funny\nkey2" => [2,2]}];
my ($fh, $filename) = tempfile(UNLINK => 1);
print $fh $json_formatter->encode($array_of_hashes->[0]), "\n";
print $fh '3 ', $json_formatter->encode($array_of_hashes->[0]), "\n";
print $fh '-1 ', $json_formatter->encode($array_of_hashes->[1]), "\n";
print $fh '1 ', $json_formatter->encode($array_of_hashes), "\n";
close($fh);

standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
    { 'cmd' => 'sleep 0', 'dataflow_file' => $filename },
    [
        [
            'DATAFLOW',
            $array_of_hashes->[0],
            undef,
        ],
        [
            'DATAFLOW',
            $array_of_hashes->[0],
            3,
        ],
        [
            'DATAFLOW',
            $array_of_hashes->[1],
            -1,
        ],
        [
            'DATAFLOW',
            $array_of_hashes,
            1,
        ],
    ],
);


done_testing();
