=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::JobErrorAdaptor

=head1 SYNOPSIS

    $dba->get_JobErrorAdaptor->register_error($job_id, $error_msg);

=head1 DESCRIPTION

    This is currently an "objectless" adaptor that simply helps to store job death events into job_error table.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::JobErrorAdaptor;

use strict;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

sub register_error {
    my ($self, $job_id, $error_msg) = @_;

    chomp $error_msg;   # we don't want that last "\n" in the database

        # (the timestamp column will be set automatically)
    my $sql = qq{
        REPLACE INTO job_error (analysis_job_id, worker_id, retry_count, status, error_msg)
                         SELECT analysis_job_id, worker_id, retry_count, status, ?
                           FROM analysis_job WHERE analysis_job_id=?
    };

    my $sth = $self->prepare( $sql );
    $sth->execute( $error_msg, $job_id );
    $sth->finish();
}

1;

