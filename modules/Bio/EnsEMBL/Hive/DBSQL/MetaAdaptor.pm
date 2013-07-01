=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor

=head1 SYNOPSIS

    $dba->get_MetaAdaptor->store( \@rows );

=head1 DESCRIPTION

    This is currently an "objectless" adaptor for storing and fetching metadata

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor;

use strict;

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'hive_meta';
}


sub store_pair {
    my ($self, $meta_key, $meta_value) = @_;

    return $self->store( { 'meta_key' => $meta_key, 'meta_value' => $meta_value } );
}


sub fetch_value_by_key {
    my ($self, $meta_key) = @_;

    my $pair = $self->fetch_by_meta_key( $meta_key );
    return $pair && $pair->{'meta_value'};
}

1;

