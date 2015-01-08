package Hive::Test::SystemCmd;

use strict;
use warnings;

use lib 't/lib/';

use Bio::EnsEMBL::Hive::Utils::Test qw(spurt);

use base qw{Hive::Config};

sub test_suite_init {

   return (
       '-inputfile'        => 'none',
       '-max_chunk_length' => 1,
       '-chunks_dir'       => '.',
       '-output_suffix'    => '.fa',
   );
}

sub pipeline_analyses {
    my $self = shift;
    return [
	{
	    -logic_name => 'system_cmd',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -input_ids => [ 
		 {
		     'cmd' => 'echo hello world >&2',
		 },
		 {
		     'cmd' => 'echo hello world >&2',
		 },
		 {
		     'cmd' => 'echo hello world',
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
    use_ok( 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd' );
}
#########################

my $dir = tempdir CLEANUP => 1;
chdir $dir;

my @argv   = Hive::Test::SystemCmd::test_suite_init('input.fa');
my $config = Hive::Test::SystemCmd->init_pipeline_here( @argv );

my $apiarist = Hive::Apiarist->new();
my $job      = $apiarist->get_a_new_job( $config->pipeline_url, 1 );
ok( $job, 'got work to do' );

my $runnable = Bio::EnsEMBL::Hive::RunnableDB::SystemCmd->new();
ok($runnable, 'instantiation');

$apiarist->runnable_a_job( $runnable, $job );
##
## do some checks
##

chdir $ENV{'EHIVE_ROOT_DIR'};

done_testing();
