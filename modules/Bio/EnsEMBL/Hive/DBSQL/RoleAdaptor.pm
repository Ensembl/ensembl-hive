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
use warnings;
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


sub get_hive_current_load {
    my $self = shift;
    my $sql = qq{
        SELECT sum(1/hive_capacity)
        FROM role
        JOIN analysis_stats USING(analysis_id)
        WHERE when_finished IS NULL
        AND hive_capacity IS NOT NULL
        AND hive_capacity>0
    };
    my $sth = $self->prepare($sql);
    $sth->execute();
    my ($current_load)=$sth->fetchrow_array();
    $sth->finish;
    return ($current_load || 0);
}


sub get_role_rank {
    my ($self, $role) = @_;

    return $self->count_all( 'analysis_id=' . $role->analysis_id . ' AND when_finished IS NULL AND role_id<' . $role->dbID );
}


sub count_active_roles {
    my ($self, $analysis_id) = @_;

    return $self->count_all( ($analysis_id ? "analysis_id=$analysis_id AND " : '') . 'when_finished IS NULL' );
}


sub print_active_role_counts {
    my $self = shift;

    my $sql = qq{
        SELECT logic_name, count(*)
        FROM role
        JOIN analysis_base a USING(analysis_id)
        WHERE when_finished IS NULL
        GROUP BY a.analysis_id
    };

    my $total_roles = 0;
    my $sth = $self->prepare($sql);
    $sth->execute();

    print "\n===== Stats of active Roles as recorded in the pipeline database: ======\n";
    while(my ($logic_name, $active_role_count) = $sth->fetchrow_array()) {
        printf("%30s : %d active Roles\n", $logic_name, $active_role_count);
        $total_roles += $active_role_count;
    }
    $sth->finish;
    printf("%30s : %d active Roles\n\n", '======= TOTAL =======', $total_roles);
}


sub fetch_all_finished_roles_with_unfinished_jobs {
    my $self = shift;

    return $self->fetch_all( "JOIN job USING(role_id) WHERE when_finished IS NOT NULL AND status NOT IN ('DONE', 'READY', 'FAILED', 'PASSED_ON') GROUP BY role_id" );
}


1;

