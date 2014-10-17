package Hive::Test::FastaFactory;

use strict;
use warnings;

use lib 't/lib/';

use Hive::Test qw{spurt};

use base qw{Hive::Config};

sub test_suite_init {
    my $fasta = shift;
    ## write some sequences
    spurt <<EOF, $fasta;
>sequence1
ATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTA
GCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGAT
CTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTG
AGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTT
ATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTA
GCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGAT
CTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTG
AGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTT
ATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTA
GCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGAT
CTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTT
>sequence2
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTC
>sequence3
ATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTA
GCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGAT
CTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTG
AGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTT
ATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTA
GCTAGTCGGTGTGTGTGTTTAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
AGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCG
ATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGACGATCTAGCAGCTGTAGCTA
GTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTCAGTCGTACGTAGCGATCTGA
CGATCTAGCAGCTGTAGCTAGTCGGTGTGTGTGTTTATCGATCGTACTGACTACTGAGTC
EOF

   return (
       '-inputfile'        => $fasta,
       '-max_chunk_length' => 1,
       '-chunks_dir'       => '.',
       '-output_suffix'    => '.fa',
   );
}

sub pipeline_analyses {
    my $self = shift;
    return [
	{
	    -logic_name => 'fasta_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
            -input_ids => [ 
		 {
		     'inputfile'         => $self->o('inputfile'),
		     'max_chunk_length'  => 20000, ## big enough for all sequences
		     'output_prefix'     => $self->o('chunks_dir').'/test1_',
		     'output_suffix'     => $self->o('output_suffix'),
		 },
		 {
		     'inputfile'         => $self->o('inputfile'),
		     'max_chunk_length'  => 200, ## smaller than all sequences
		     'output_prefix'     => $self->o('chunks_dir').'/test2_',
		     'output_suffix'     => $self->o('output_suffix'),
		 },
		 {
		     'inputfile'         => $self->o('inputfile'),
		     'max_chunk_length'  => 1000, ## smaller than two combined sequences
		     'output_prefix'     => $self->o('chunks_dir').'/test3_',
		     'output_suffix'     => $self->o('output_suffix'),
		 },
		],
	}
	];
}

package main;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};
use Hive::Apiarist;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory' );
}
#########################

my $dir = tempdir CLEANUP => 1;
chdir $dir;

my @argv   = Hive::Test::FastaFactory::test_suite_init('input.fa');
my $config = Hive::Test::FastaFactory->init_pipeline_here( @argv );

my $apiarist = Hive::Apiarist->new();
my $job      = $apiarist->get_a_new_job( $config->pipeline_url, 1 );
ok( $job, 'got work to do' );

my $runnable = Bio::EnsEMBL::Hive::RunnableDB::FastaFactory->new();
ok($runnable, 'instantiation');

run_job( $runnable, $job );
##
## do some checks
##
my $expected_filename = 'test1_1.fa';
ok(-e $expected_filename, 'output file exists');

is((stat($expected_filename))[7], (stat('input.fa'))[7], 'file size of input == output');

my @all_files = glob('test1_*.fa');
is(@all_files, 1, 'exactly one output file - test 1');

## 
## next job
##
$job = $apiarist->get_a_new_job( $config->pipeline_url, 2 );
ok( $job, 'got more work to do' );

run_job( $runnable, $job );

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
$job = $apiarist->get_a_new_job( $config->pipeline_url, 3 );
ok( $job, 'got more work to do' );

run_job( $runnable, $job );

$expected_filename = 'test3_1.fa';
ok(-e $expected_filename, 'output file exists');

@all_files = glob('test3_*.fa');
is(@all_files, 2, 'correct number of output files - test 3');
# diag "@all_files";

foreach my $file(@all_files) {
    my $exp_size = $expected_properties->{$file}[0];
    is((stat($file))[7], $exp_size, "file '$file' has expected file size ($exp_size)");
}


sub run_job {
    my ($runnable, $job) = @_;
    $job->param_init( 
	$runnable->strict_hash_format(),
	$runnable->param_defaults(), 
	$job->input_id(),
	);
    $runnable->input_job( $job );    
    $runnable->fetch_input();
    $runnable->run();
    $runnable->write_output();
}

chdir $ENV{'EHIVE_ROOT_DIR'};

done_testing();
