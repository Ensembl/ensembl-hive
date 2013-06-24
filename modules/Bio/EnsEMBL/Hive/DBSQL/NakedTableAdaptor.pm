=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor

=head1 SYNOPSIS

    $naked_table_adaptor = $dba->get_NakedTableAdaptor;
    $naked_table_adaptor = $naked_table->adaptor;

=head1 DESCRIPTION

    This module together with its data container are used to enable dataflow into arbitrary tables (rather than just 'job' table).
    Due to the implementation of EnsEMBL Registry code, NakedTable objects know *where* to dataflow, and NakedTableAdaptor knows *how* to dataflow.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor;

use strict;
use Bio::EnsEMBL::Hive::NakedTable;

use base ('Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor');


sub slicer {    # take a slice of the hashref (if only we could inline in Perl!)
    my ($self, $object, $fields) = @_;

    return [ @$object{@$fields} ];
}


sub objectify {    # pretend the hashref becomes an object (if only we could inline in Perl!)
    return pop @_;
}


sub mark_stored {
    my ($self, $hashref, $dbID) = @_;

    if(my $autoinc_id = $self->autoinc_id()) {
        $hashref->{$autoinc_id} = $dbID;
    }
}


sub keys_to_columns {
    my ($self, $object) = @_;

    my $sorted_keys = [ sort keys %$object ];

    return ( $sorted_keys, join(', ', @$sorted_keys) );
}

1;

