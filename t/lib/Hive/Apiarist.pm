package Hive::Apiarist;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

sub new {
    my $pkg = shift;
    return bless {}, $pkg;
}

sub get_a_new_job {
    my ($self, $url, $id) = @_;

    my $dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $url );
    my $ja  = $dba->get_JobAdaptor();
    my $job = $ja->fetch_by_dbID( $id );

    return $job;
}

sub runnable_a_job {
    my ($self, $runnable, $job) = @_;
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

1;
