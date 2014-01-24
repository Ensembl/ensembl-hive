=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor

=head1 SYNOPSIS

    $resource_description_adaptor = $db_adaptor->get_ResourceDescriptionAdaptor;

    $resource_description_adaptor = $resource_description_object->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class ResourceDescription.
    There should be just one per application and database connection.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

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

