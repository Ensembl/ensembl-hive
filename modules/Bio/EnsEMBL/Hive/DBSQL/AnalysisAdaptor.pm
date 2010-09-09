=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor

=head1 SYNOPSIS

  $analysis_adaptor = $db_adaptor->get_AnalysisAdaptor;

=head1 DESCRIPTION

  This module extends EnsEMBL Core's AnalysisAdaptor, adding some Hive-specific stuff.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor;

use strict;

use base ('Bio::EnsEMBL::DBSQL::AnalysisAdaptor');


=head2 fetch_by_logic_name_or_url

    Description: given a URL gets the analysis from URLFactory, otherwise fetches it from the db

=cut

sub fetch_by_logic_name_or_url {
    my $self                = shift @_;
    my $logic_name_or_url   = shift @_;

    if($logic_name_or_url =~ m{^\w+://}) {
        return Bio::EnsEMBL::Hive::URLFactory->fetch($logic_name_or_url, $self->db);
    } else {
        return $self->fetch_by_logic_name($logic_name_or_url);
    }
}


=head2 fetch_by_url_query

    Description: fetches the analysis either by logic_name or by dbID (either coming from the tail of the URL)

=cut

sub fetch_by_url_query {
    my ($self, $field_name, $field_value) = @_;

    if(!$field_name or !$field_value) {

        return;

    } elsif($field_name eq 'logic_name') {

        return $self->fetch_by_logic_name($field_value);

    } elsif($field_name eq 'dbID') {

        return $self->fetch_by_dbID($field_value);

    }
}


1;
