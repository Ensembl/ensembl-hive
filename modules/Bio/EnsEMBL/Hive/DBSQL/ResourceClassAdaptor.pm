=pod

=head1 NAME

  Bio::EnsEMBL::Hive::DBSQL::ResourceClassAdaptor

=head1 SYNOPSIS

  $resource_class_adaptor = $db_adaptor->get_ResourceClassAdaptor;

  $resource_class_adaptor = $resource_class_object->adaptor;

=head1 DESCRIPTION

  Module to encapsulate all db access for persistent class ResourceClass.
  There should be just one per application and database connection.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::ResourceClassAdaptor;

use strict;
use Bio::EnsEMBL::Hive::ResourceClass;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'resource_class';
}


sub default_insertion_method {
    return 'INSERT_IGNORE';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::ResourceClass';
}

1;

