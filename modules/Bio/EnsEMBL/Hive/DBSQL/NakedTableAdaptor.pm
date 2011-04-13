=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor

=head1 SYNOPSIS

    $naked_table_adaptor = $dba->get_NakedTableAdaptor;

    $naked_table_adaptor = $naked_table->adaptor;

=head1 DESCRIPTION

    This module together with its data container are used to enable dataflow into arbitrary tables (rather than just job).

    NakedTable objects know *where* to dataflow, and NakedTableAdaptor knows *how* to dataflow.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor;

use strict;
use Bio::EnsEMBL::Hive::NakedTable;

use base ('Bio::EnsEMBL::DBSQL::BaseAdaptor');

sub create_new {
    my $self = shift @_;

    return Bio::EnsEMBL::Hive::NakedTable->new(@_, -ADAPTOR => $self);
}

sub dataflow {
    my ( $self, $naked_table, $output_ids ) = @_;

    return unless(@$output_ids);

    my $table_name = $naked_table->table_name();

    my $insertion_method = uc( $naked_table->insertion_method() );  # INSERT, INSERT_IGNORE or REPLACE
    $insertion_method =~ s/_/ /g;

        # NB: here we assume all hashes will have the same keys (and also the same order):
    my @column_names = keys %{$output_ids->[0]};

        # By using question marks you can insert true NULLs by setting corresponding values to undefs:
    my $sql = "$insertion_method INTO $table_name (".join(', ', @column_names).') VALUES ('.join(',', (('?') x scalar(@column_names))).')';
    my $sth = $self->prepare( $sql );

    my @insert_ids = ();

    foreach my $data_hash (@$output_ids) {
        $sth->execute( values %$data_hash ); # Perl manual promises that the order of "keys" will be the same as the order of "values", so no need to sort.
        push @insert_ids, $sth->{'mysql_insertid'}; # capture it just in case

    }

    $sth->finish();

    return \@insert_ids;
}

1;

