=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::SemaphoreAdaptor

=head1 SYNOPSIS

    $semaphore_adaptor = $db_adaptor->get_SemaphoreAdaptor;

    $semaphore_adaptor = $semaphore_object->adaptor;

=head1 DESCRIPTION

    Module to encapsulate all db access for persistent class Semaphore.
    There should be just one per application and database connection.

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::SemaphoreAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'semaphore';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Semaphore';
}


sub increment_column_by_inc_and_id {
    my ($self, $column_name, $inc, $semaphore_id) = @_;

    my $sql = "UPDATE semaphore SET $column_name = $column_name + $inc WHERE semaphore_id = $semaphore_id";

    $self->dbc->protected_prepare_execute( [ $sql ],
        sub { my ($after) = @_; $self->db->get_LogMessageAdaptor->store_hive_message( "performing $sql".$after, 'INFO' ); }
    );
}


1;
