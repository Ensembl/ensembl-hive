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

1;
