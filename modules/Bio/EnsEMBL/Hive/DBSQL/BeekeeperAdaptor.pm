=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::BeekeeperAdaptor

=head1 DESCRIPTION

    This is the adaptor for Bio::EnsEMBL::Hive::Beekeeper

    It contains all the beekeeper-management methods that are
    called by beekeeper.pl and requir the database.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::BeekeeperAdaptor;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');

# --------------------------------- ObjectAdaptor implementation ---------------------------------------

sub default_table_name {
    return 'beekeeper';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Beekeeper';
}


# --------------------------------- Beekeeper methods ---------------------------------------

=head2 find_live_beekeepers_in_my_meadow

  Arg[1]      : Bio::EnsEMBL::Hive::Beekeeper $ref_beekeeper
  Example     : my $live_beekeepers_in_my_meadow = $bk_adaptor->find_live_beekeepers_in_my_meadow($beekeeper);
  Description : Returns all the beekeepers registered on the same host as $ref_beekeeper that are still alive.
  Returntype  : Arrayref of Bio::EnsEMBL::Hive::Beekeeper
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub find_live_beekeepers_in_my_meadow {
    my ($self, $ref_beekeeper) = @_;

    my $filter = sprintf("meadow_host = '%s' AND beekeeper_id != %d AND cause_of_death IS NULL", $ref_beekeeper->meadow_host, $ref_beekeeper->dbID);
    return $self->fetch_all($filter);
}


=head2 bury_other_beekeepers

  Arg[1]      : Bio::EnsEMBL::Hive::Beekeeper $ref_beekeeper
  Example     : $bk_adaptor->bury_other_beekeepers($ref_beekeeper);
  Description : Calls find_live_beekeepers_in_my_meadow() and buries the beekeepers that
                are not running any more (not find with `ps`)
  Returntype  : none
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub bury_other_beekeepers {
    my ($self, $ref_beekeeper) = @_;

    my $allegedly_live_beekeepers_in_my_meadow = $self->find_live_beekeepers_in_my_meadow($ref_beekeeper);
    foreach my $beekeeper_to_check (@$allegedly_live_beekeepers_in_my_meadow) {
        my $pid = $beekeeper_to_check->process_id;
        my $cmd = qq{ps -p $pid -f | fgrep beekeeper.pl};
        my $beekeeper_entry = qx{$cmd};

        unless ($beekeeper_entry) {
            $beekeeper_to_check->set_cause_of_death('DISAPPEARED');
        }
    }
}


=head2 reload_beekeeper_is_blocked

  Arg[1]      : Bio::EnsEMBL::Hive::Beekeeper $beekeeper
  Example     : my $is_blocked = $bk_adaptor->reload_beekeeper_is_blocked($beekeeper);
  Description : Updates the object with the freshest value of is_blocked coming from the database
                for this beekeeper, and return the new value.
  Returntype  : none
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub reload_beekeeper_is_blocked {
    my ($self, $beekeeper) = @_;

    my $query = 'SELECT is_blocked FROM beekeeper WHERE beekeeper_id = ?';

    my $sth = $self->dbc->prepare($query);
    $sth->execute($beekeeper->dbID);

    my ($is_blocked) = $sth->fetchrow_array();
    $sth->finish;

    $beekeeper->is_blocked( $is_blocked );

    return $is_blocked;
}


=head2 block_all_alive_beekeepers

  Example     : $bk_adaptor->block_all_alive_beekeepers();
  Description : Set is_blocked for all beekeepers known to the
                pipeline which haven't died yet. Part of the "shut
                everything down" feature - as eHive stands we cannot
                tell other beekeepers to kill their respective active
                workers (unless said workers happen to belong to the
                same meadow, in which case we can essentially hijack
                them) but at least we can prevent them from spawning
                new workers.
  Returntype  : none
  Exception   : none
  Caller      : beekeeper.pl
  Status      : Stable

=cut

sub block_all_alive_beekeepers {
    my ( $self ) = @_;

    my $statement = 'UPDATE beekeeper SET is_blocked = 1 WHERE cause_of_death IS NULL';
    my $sth = $self->dbc()->prepare( $statement );
    $sth->execute();
    $sth->finish();

    return;
}


1;
