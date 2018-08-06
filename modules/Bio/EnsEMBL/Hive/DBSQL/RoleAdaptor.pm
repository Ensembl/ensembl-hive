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

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');


sub default_table_name {
    return 'role';
}

sub default_input_column_mapping {
    my $self    = shift @_;
    return  {
        # Add another column based on when_started
        'when_started' => 'when_started, ' . $self->dbc->_interval_seconds_sql('when_started') . ' seconds_since_when_started',
    };
}

sub object_class {
    return 'Bio::EnsEMBL::Hive::Role';
}


sub finalize_role {
    my ($self, $role, $release_undone_jobs) = @_;

    $role->when_finished( 'CURRENT_TIMESTAMP' );
    $self->update_when_finished( $role );

    $self->db->get_AnalysisStatsAdaptor->increment_a_counter( 'num_running_workers', -1, $role->analysis_id );

    if( $release_undone_jobs ) {
        $self->db->get_AnalysisJobAdaptor->release_undone_jobs_from_role( $role );
    }

        # Re-sync the analysis_stats when a worker dies as part of dynamic sync system.
        # It will also re-calculate num_running_workers (from active roles)
        # so no further adjustment should be necessary.
    $self->db->get_WorkerAdaptor->safe_synchronize_AnalysisStats( $role->analysis->stats );
}


sub fetch_last_unfinished_by_worker_id {
    my ($self, $worker_id) = @_;

    return $self->fetch_all( "WHERE worker_id=$worker_id AND when_finished IS NULL ORDER BY role_id DESC LIMIT 1", 1 );
}


sub get_hive_current_load {
    my $self = shift;
    my $sql = qq{
        SELECT sum(1/hive_capacity)
        FROM role
        JOIN analysis_base USING(analysis_id)
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

    return $self->fetch_all( "JOIN job USING(role_id) WHERE when_finished IS NOT NULL AND status IN ($Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor::ALL_STATUSES_OF_TAKEN_JOBS) GROUP BY role_id" );
}


sub fetch_all_unfinished_roles_of_dead_workers {
    my $self = shift;

    return $self->fetch_all( "JOIN worker USING(worker_id) WHERE when_finished IS NULL AND status='DEAD'" );
}


1;

