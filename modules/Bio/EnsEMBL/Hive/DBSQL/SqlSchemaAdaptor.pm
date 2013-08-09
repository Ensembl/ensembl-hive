=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor

=head1 SYNOPSIS

    Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version();

=head1 DESCRIPTION

    This is currently an "objectless" adaptor for finding out the apparent code's SQL schema version

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;

use strict;


sub get_sql_schema_patches {
    my $after_version = pop @_ || 0;

    if(my $hive_root_dir = $ENV{'EHIVE_ROOT_DIR'} ) {

        my @patches = split(/\n/, `ls -1 $hive_root_dir/sql/patch_20*.sql`);

        return [ @patches[$after_version..scalar(@patches)-1] ];
    } else {
        warn "WARNING: 'EHIVE_ROOT_DIR' environment variable has not been set, things may start crashing soon\n";
        return [];
    }
}


sub get_code_sql_schema_version {

    return scalar( @{ get_sql_schema_patches() } );
}

1;

