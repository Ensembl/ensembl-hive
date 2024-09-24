=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Beekeeper

=head1 DESCRIPTION

    A light-weight object to record a Beekeeper instance.

    This object does not perform any of tasks beekeeper do (submitting jobs, etc),
    its purpose is merely to record the fact that a beekeeper has been run, and
    update its status.

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


package Bio::EnsEMBL::Hive::Beekeeper;

use strict;
use warnings;

use base ( 'Bio::EnsEMBL::Hive::Storable' );    # To enable dbID() and adaptor()


=head2 new_from_Valley

  Example     : my $new_from_Valley = Bio::EnsEMBL::Hive::Beekeeper->new_from_Valley($valley);
  Description : A specific constructor that sets all the fields according to the given Valley.
  Returntype  : Bio::EnsEMBL::Hive::Beekeeper
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub new_from_Valley {
    my ($class, $valley, @args) = @_;

    my ($meadow, $pid, $meadow_host, $meadow_user) = $valley->whereami;
    unless($meadow->can('deregister_local_process')) {
        die "beekeeper.pl detected it has been itself submitted to '".$meadow->type."/".$meadow->cached_name."', but this mode of operation is not supported.\n"
           ."Please just run beekeeper.pl on a farm head node, preferably from under a 'screen' session.\n";
    }
    $meadow->deregister_local_process();

    return $class->SUPER::new(
        'meadow'        => $meadow_host,
        'meadow_host'   => $meadow_host,
        'meadow_user'   => $meadow_user,
        'process_id'    => $pid,
        @args,
    );
}


# --------------------------------- Getter / Setters ---------------------------------------

sub meadow_host {
    my $self = shift;
    $self->{'_meadow_host'} = shift if(@_);
    return $self->{'_meadow_host'};
}

sub meadow_user {
    my $self = shift;
    $self->{'_meadow_user'} = shift if(@_);
    return $self->{'_meadow_user'};
}

sub process_id {
    my $self = shift;
    $self->{'_process_id'} = shift if(@_);
    return $self->{'_process_id'};
}

sub is_blocked {
    my $self = shift;
    $self->{'_is_blocked'} = shift if(@_);
    return $self->{'_is_blocked'};
}

sub cause_of_death {
    my $self = shift;
    $self->{'_cause_of_death'} = shift if(@_);
    return $self->{'_cause_of_death'};
}

sub sleep_minutes {
    my $self = shift;
    $self->{'_sleep_minutes'} = shift if(@_);
    return $self->{'_sleep_minutes'};
}

sub analyses_pattern {
    my $self = shift;
    $self->{'_analyses_pattern'} = shift if(@_);
    return $self->{'_analyses_pattern'};
}

sub loop_limit {
    my $self = shift;
    $self->{'_loop_limit'} = shift if(@_);
    return $self->{'_loop_limit'};
}

sub loop_until {
    my $self = shift;
    $self->{'_loop_until'} = shift if(@_);
    return $self->{'_loop_until'};
}

sub options {
    my $self = shift;
    $self->{'_options'} = shift if(@_);
    return $self->{'_options'};
}

sub meadow_signatures {
    my $self = shift;
    $self->{'_meadow_signatures'} = shift if(@_);
    return $self->{'_meadow_signatures'};
}


# --------------------------------- Convenient methods ---------------------------------------

sub meadow {
    my $self = shift;
    $self->{'_meadow'} = shift if(@_);
    return $self->{'_meadow'};
}


=head2 set_cause_of_death

  Example     : $beekeeper->set_cause_of_death('LOOP_LIMIT');
  Description : Set the "cause of death" of this beekeeper in the object and in the database.
  Returntype  : none
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub set_cause_of_death {
    my ($self, $cause_of_death) = @_;

    $self->cause_of_death( $cause_of_death );
    $self->adaptor->update_cause_of_death($self) if $self->adaptor;
}


=head2 check_if_blocked

  Example     : my $check_if_blocked = $beekeeper->check_if_blocked();
  Description : Updates the object with the freshest value of is_blocked coming from the database
                for this beekeeper, and return the new value.
  Returntype  : Boolean
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub check_if_blocked {
    my ($self) = @_;
    $self->adaptor->reload_beekeeper_is_blocked($self) if $self->adaptor;
    return $self->is_blocked;
}


=head2 toString

  Example     : print $beekeeper->toString();
  Description : Produces a string summary of properties of this beekeeper.
  Returntype  : String
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub toString {
    my ( $self ) = @_;

    return join( ', ',
            'process=' . $self->meadow_user() . '@' . $self->meadow_host() . '#' . $self->process_id(),
            "options='" . $self->options() . "'",
    );
}


1;

