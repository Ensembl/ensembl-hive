=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::StatementHandle

=head1 SYNOPSIS

    Do not use this class directly.
    It will automatically be used by the Bio::EnsEMBL::Hive::DBSQL::DBConnection class.

=head1 DESCRIPTION

    This class extends DBD::mysql::st so that the DESTROY method may be
    overridden.  If the DBConnection::disconnect_when_inactive flag is set
    this statement handle will cause the database connection to be closed
    when it goes out of scope and there are no other open statement handles.

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


package Bio::EnsEMBL::Hive::DBSQL::StatementHandle;

use strict;
use warnings;

use DBI;
use Bio::EnsEMBL::Hive::Utils ('throw');

use base ('DBI::st');


# As DBD::mysql::st is a tied hash can't store things in it,
# so have to have parallel hash
my %dbchash;
my %dbc_sql_hash;


sub dbc {
    my $self = shift;

    if (@_) {
        my $dbc = shift;
        if(!defined($dbc)) {
            # without delete key space would grow indefinitely causing mem-leak
            delete($dbchash{$self});
        } else {
            $dbchash{$self} = $dbc;
        }
    }

    return $dbchash{$self};
}


sub sql {
    my $self = shift;

    if (@_) {
        my $sql = shift;
        if(!defined($sql)) {
            # without delete key space would grow indefinitely causing mem-leak
            delete($dbc_sql_hash{$self});
        } else {
            $dbc_sql_hash{$self} = $sql;
        }
    }

    return $dbc_sql_hash{$self};
}


sub DESTROY {
    my ($self) = @_;

    my $dbc = $self->dbc;
    $self->dbc(undef);
    my $sql = $self->sql;
    $self->sql(undef);

    # Re-bless into DBI::st so that superclass destroy method is called if
    # it exists (it does not exist in all DBI versions).
    bless( $self, 'DBI::st' );

    # The count for the number of kids is decremented only after this
    # function is complete. Disconnect if there is 1 kid (this one)
    # remaining.
    if (   $dbc
        && $dbc->disconnect_when_inactive()
        && $dbc->connected
        && ( $dbc->db_handle->{Kids} == 1 ) ) {

        if ( $dbc->disconnect_if_idle() ) {
            warn("Problem disconnect $self around sql = $sql\n");
        }
    }
}

1;

