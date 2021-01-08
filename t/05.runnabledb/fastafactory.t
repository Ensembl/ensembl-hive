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
use File::Basename;
use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

# Where the Fasta file should be
my $inputfile = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ).'/input_fasta.fa';

my $dir = tempdir CLEANUP => 1;
my $original = Cwd::getcwd;
chdir $dir;

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
    {
        'inputfile'         => $inputfile,
        'max_chunk_length'  => 20000, ## big enough for all sequences
        'output_prefix'     => './test1_',
        'output_suffix'     => '.fa',
    },
    [
        [
            'DATAFLOW',
            {
                'chunk_number' => 1,
                'chunk_length' => 3360,
                'chunk_size' => 3,
                'chunk_name' => './test1_1.fa'
            },
            2
        ]
    ],
);


##
## do some checks
##
my $expected_filename = 'test1_1.fa';
ok(-e $expected_filename, 'output file exists');

is((stat($expected_filename))[7], (stat($inputfile))[7], 'file size of input == output');

my @all_files = glob('test1_*.fa');
is(@all_files, 1, 'exactly one output file - test 1');


## 
## next job
##
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
    {
        'inputfile'         => $inputfile,
        'max_chunk_length'  => 200, ## smaller than all sequences
        'output_prefix'     => './test2_',
        'output_suffix'     => '.fa',
    },
    [
        [
            'DATAFLOW',
            {
                'chunk_number' => 1,
                'chunk_length' => 640,
                'chunk_size' => 1,
                'chunk_name' => './test2_1.fa'
            },
            2
        ],
        [
            'DATAFLOW',
            {
                'chunk_number' => 2,
                'chunk_length' => 1280,
                'chunk_size' => 1,
                'chunk_name' => './test2_2.fa'
            },
            2
        ],
        [
            'DATAFLOW',
            {
                'chunk_number' => 3,
                'chunk_length' => 1440,
                'chunk_size' => 1,
                'chunk_name' => './test2_3.fa'
            },
            2
        ],
    ],
);


@all_files = glob('test2_*.fa');
is(@all_files, 3, 'correct number of output files - test 2');
# diag "@all_files";

my $expected_properties = {
    'test2_1.fa' => [ 662 ],
    'test2_2.fa' => [ 1313 ],
    'test2_3.fa' => [ 1475 ],

    'inside/test3_1.embl' => [ 3067 ],
    'inside/test3_2.embl' => [ 2142 ],

    'test4_1.fa' => [ 402 ],
    'test4_2.fa' => [ 386 ],
    'test4_3.fa' => [ 408 ],
    'test4_4.fa' => [ 408 ],
    'test4_5.fa' => [ 408 ],
    'test4_6.fa' => [ 368 ],
    'test4_7.fa' => [ 408 ],
    'test4_8.fa' => [ 408 ],
    'test4_9.fa' => [ 408 ],
    '0/test4_10.fa' => [ 204 ],
};

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}

## 
## next job
##
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
    {
        'inputfile'         => $inputfile,
        'max_chunk_length'  => 1000, ## smaller than two combined sequences
        'output_prefix'     => './test3_',
        'output_suffix'     => '.embl',
        'output_dir'        => 'inside',
        'output_format'     => 'embl',
    },
    [
        [
            'DATAFLOW',
            {
                'chunk_number' => 1,
                'chunk_length' => 1920,
                'chunk_size' => 2,
                'chunk_name' => 'inside/test3_1.embl'
            },
            2
        ],
        [
            'DATAFLOW',
            {
                'chunk_number' => 2,
                'chunk_length' => 1440,
                'chunk_size' => 1,
                'chunk_name' => 'inside/test3_2.embl'
            },
            2
        ],
    ],
);

@all_files = glob('inside/test3_*.embl');
is(@all_files, 2, 'correct number of output files - test 3');
# diag "@all_files";

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}

##
## next job
##

# New input file that has shorter sequences
my $new_inputfile = 'test_input.fa';
system(q{awk '!($0 ~ /^>/) {print ">seq"NR; print $0}' }.qq{ $inputfile > $new_inputfile});

standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory', {
        'inputfile'         => $new_inputfile,
        'max_chunk_length'  => 300, ## such that some files will be in sub-directories
        'output_prefix'     => './test4_',
        'output_suffix'     => '.fa',
        'hash_directories'  => 1,
});

@all_files = (glob('test4_*.fa'), glob('0/test4_*.fa'));
is(@all_files, 10, 'correct number of output files - test 4');
# diag "@all_files";

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}

# And now output_dir with hash_directories
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory', {
        'inputfile'         => $new_inputfile,
        'max_chunk_length'  => 300, ## such that some files will be in sub-directories
        'output_prefix'     => 'test4_',
        'output_suffix'     => '.fa',
        'output_dir'        => 'in4',
        'hash_directories'  => 1,
});

@all_files = (glob('in4/test4_*.fa'), glob('in4/0/test4_*.fa'));
is(@all_files, 10, 'correct number of output files - test 4');
# diag "@all_files";

foreach my $file (@all_files) {
    my $clean_filename = $file;
    $clean_filename =~ s/in4\///;
    my $exp_size = $expected_properties->{$clean_filename}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}


# Try the compressed mode
my $compressed_inputfile = "comp_input_fasta.fa.gz";
system("gzip < $inputfile > $compressed_inputfile");

standaloneJob(
    'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
    {
        'inputfile'         => $compressed_inputfile,
        'max_chunk_length'  => 20000, ## big enough for all sequences
        'output_prefix'     => './test5_',
        'output_suffix'     => '.fa',
    },
    [
        [
            'DATAFLOW',
            {
                'chunk_number' => 1,
                'chunk_length' => 3360,
                'chunk_size' => 3,
                'chunk_name' => './test5_1.fa'
            },
            2
        ]
    ],
);

##
## do some checks
##
$expected_filename = 'test5_1.fa';
ok(-e $expected_filename, 'output file exists');

is((stat($expected_filename))[7], (stat($inputfile))[7], 'file size of input == output');

@all_files = glob('test5_*.fa');
is(@all_files, 1, 'exactly one output file - test 5 (like 1)');


done_testing();

chdir $original;

