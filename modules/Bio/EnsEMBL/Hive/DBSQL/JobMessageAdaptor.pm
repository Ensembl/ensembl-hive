=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::JobMessageAdaptor

=head1 SYNOPSIS

    $dba->get_JobMessageAdaptor->register_message($job_id, $msg, $is_error);

=head1 DESCRIPTION

    This is currently an "objectless" adaptor that simply helps to store messages thrown by jobs into job_message table.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::JobMessageAdaptor;

use strict;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

sub register_message {
    my ($self, $job_id, $msg, $is_error) = @_;

    chomp $msg;   # we don't want that last "\n" in the database

        # (the timestamp 'moment' column will be set automatically)
    my $sql = qq{
        REPLACE INTO job_message (analysis_job_id, worker_id, analysis_id, retry_count, status, msg, is_error)
                           SELECT analysis_job_id, worker_id, analysis_id, retry_count, status, ?, ?
                             FROM analysis_job WHERE analysis_job_id=?
    };

    my $sth = $self->prepare( $sql );
    $sth->execute( $msg, $is_error, $job_id );
    $sth->finish();
}

1;

