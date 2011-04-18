=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor

=head1 SYNOPSIS

  $resource_description_adaptor = $db_adaptor->get_ResourceDescriptionAdaptor;

  $resource_description_adaptor = $resource_description_object->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class ResourceDescription.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor;

use strict;
use Bio::EnsEMBL::Hive::ResourceDescription;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'resource_description';
}


sub default_insertion_method {
    return 'REPLACE';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::ResourceDescription';
}

1;

