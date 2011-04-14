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

# No, you could not just use the Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor instead of NakedTableAdaptor
# because AUTOLOAD will be creating class-specific methods and you don't want to clutter BaseAdaptor's namespace.

1;

