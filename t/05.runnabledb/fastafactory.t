
use strict;
use warnings;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(standaloneJob);

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory' );
}
#########################

my $inputfile = $ENV{EHIVE_ROOT_DIR}.'/t/input_fasta.fa';

my $dir = tempdir CLEANUP => 1;
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
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory', {
        'inputfile'         => $inputfile,
        'max_chunk_length'  => 200, ## smaller than all sequences
        'output_prefix'     => './test2_',
        'output_suffix'     => '.fa',
});


$expected_filename = 'test2_1.fa';
ok(-e $expected_filename, 'output file exists');

@all_files = glob('test2_*.fa');
is(@all_files, 3, 'correct number of output files - test 2');
# diag "@all_files";

my $expected_properties = {
    'test2_1.fa' => [ 662 ],
    'test2_2.fa' => [ 1313 ],
    'test2_3.fa' => [ 1475 ],
    'test2_4.fa' => [ 0 ],

    'test3_1.fa' => [ 1975 ],
    'test3_2.fa' => [ 1475 ],
    'test3_3.fa' => [ 0 ],
    'test3_4.fa' => [ 0 ],
};

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}

## 
## next job
##
standaloneJob('Bio::EnsEMBL::Hive::RunnableDB::FastaFactory', {
        'inputfile'         => $inputfile,
        'max_chunk_length'  => 1000, ## smaller than two combined sequences
        'output_prefix'     => './test3_',
        'output_suffix'     => '.fa',
});

$expected_filename = 'test3_1.fa';
ok(-e $expected_filename, 'output file exists');

@all_files = glob('test3_*.fa');
is(@all_files, 2, 'correct number of output files - test 3');
# diag "@all_files";

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}

chdir $ENV{'EHIVE_ROOT_DIR'};

done_testing();
