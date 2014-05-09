=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::RoleAdaptor

=head1 SYNOPSIS

    $role_adaptor = $db_adaptor->get_RoleAdaptor;

    $role_adaptor = $role_object->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class Role.
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


package Bio::EnsEMBL::Hive::DBSQL::RoleAdaptor;

use strict;
use Bio::EnsEMBL::Hive::Role;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'role';
}


sub default_insertion_method {
    return 'INSERT';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Role';
}


sub finalize_role {
    my ($self, $role) = @_;

    my $role_id         = $role->dbID;
    my $when_finished   = $role->when_finished ? "'".$role->when_finished."'" : 'CURRENT_TIMESTAMP';

    my $sql = "UPDATE role SET when_finished=$when_finished WHERE role_id=$role_id";

    $self->dbc->do( $sql );
}


sub fetch_last_by_worker_id {
    my ($self, $worker_id) = @_;

    return $self->fetch_all( "WHERE worker_id=$worker_id ORDER BY when_started DESC LIMIT 1", 1 );
}

1;

