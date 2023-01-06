=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Valley

=head1 DESCRIPTION

    A Valley represents a collection of available Meadows.

    Certain methods fit better with the concept of Valley -
    such as identifying all dead workers, or killing a particular one given worker_id.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Valley;

use strict;
use warnings;
use List::Util ('sum');
use Sys::Hostname ('hostname');
use Bio::EnsEMBL::Hive::Utils ('find_submodules', 'whoami');
use Bio::EnsEMBL::Hive::Limiter;

use base ('Bio::EnsEMBL::Hive::Configurable');


sub meadow_class_path {

    return 'Bio::EnsEMBL::Hive::Meadow';
}


our $_loaded_meadow_drivers;

sub loaded_meadow_drivers {

    unless( $_loaded_meadow_drivers ) {
        foreach my $meadow_class (@{ $_loaded_meadow_drivers = Bio::EnsEMBL::Hive::Utils::find_submodules( meadow_class_path() ) }) {
            eval "require $meadow_class";
            die $@ if($@);          # Even if the Meadow is unavailable, we still expect all the drivers that are in the path to compile correctly.
        }
    }
    return $_loaded_meadow_drivers;
}


sub new {
    my ($class, $config, $default_meadow_type, $pipeline_name) = @_;

    my $self = bless {}, $class;

    $self->config( $config );
    $self->context( [ 'Valley' ] );

    my $amh = $self->available_meadow_hash( {} );

        # make sure modules are loaded and available ones are checked prior to setting the current one:
    foreach my $meadow_class (@{ $self->loaded_meadow_drivers }) {

        if( $meadow_class->check_version_compatibility
        and (my $name = $meadow_class->name)) {      # the assumption is if we can get a name, it is available

            my $meadow_object            = $meadow_class->new( $config, $name );

            $meadow_object->pipeline_name( $pipeline_name ) if($pipeline_name);

            $amh->{$meadow_class->type} = $meadow_object;
        }
    }

    $self->set_default_meadow_type($default_meadow_type);     # run this method even if $default_meadow_type was not specified

    return $self;
}


sub available_meadow_hash {
    my $self = shift @_;

    if(@_) {
        $self->{_available_meadow_hash} = shift @_;
    }   
    return $self->{_available_meadow_hash};
}


sub get_available_meadow_list {     # this beautiful one-liner pushes $local to the bottom of the list
    my $self = shift @_;

    my $local = $self->meadow_class_path . '::LOCAL';

    return [ sort { (ref($a) eq $local) or -(ref($b) eq $local) } values %{ $self->available_meadow_hash } ];
}


sub set_default_meadow_type {
    my ($self, $default_meadow_type) = @_;

    if($default_meadow_type) {
        if( my $default_meadow = $self->available_meadow_hash->{$default_meadow_type} ) {   # store if available
            $self->{_default_meadow} = $default_meadow;
        } else {
            die "Meadow '$default_meadow_type' does not seem to be available on this machine, please investigate";
        }
    } else {
        $self->{_default_meadow} = $self->get_available_meadow_list->[0];     # take the first from preference list
    }
}


sub get_default_meadow {
    my $self = shift @_;

    return $self->{_default_meadow};
}


sub find_available_meadow_responsible_for_worker {
    my ($self, $worker) = @_;

    if( my $meadow = $self->available_meadow_hash->{$worker->meadow_type} ) {
        if($meadow->cached_name eq $worker->meadow_name) {
            return $meadow;
        }
    }
    return undef;
}


sub whereami {
    my $self = shift @_;

    my $meadow_user = Bio::EnsEMBL::Hive::Utils::whoami();

    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        my $pid;
        my $meadow_host;
        eval {
                # get_current_worker_process_id() is expected to die if the pid
                # cannot be determined. With the eval{} and the unless{} it will
                # skip the meadow and try the next one.
            $pid            = $meadow->get_current_worker_process_id();
            $meadow_host    = $meadow->get_current_hostname();
        };
        unless($@) {
            return ($meadow, $pid, $meadow_host, $meadow_user);
        }
    }
    die "Could not determine the Meadow, please investigate";
}


sub generate_limiters {
    my ($self, $reconciled_worker_statuses) = @_;

    my $valley_running_worker_count             = 0;
    my %meadow_capacity_limiter_hashed_by_type  = ();

    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        my $this_worker_count   = scalar( @{ $reconciled_worker_statuses->{ $meadow->signature }{ 'RUN' } || [] } );

        $valley_running_worker_count                           += $this_worker_count;

        my $available_worker_slots = defined($meadow->config_get('TotalRunningWorkersMax'))
            ? $meadow->config_get('TotalRunningWorkersMax') - $this_worker_count
            : undef;

            # so the hash will contain limiters for every meadow_type, but not all of them active:
        $meadow_capacity_limiter_hashed_by_type{ $meadow->type } = Bio::EnsEMBL::Hive::Limiter->new( "Number of workers in '".$meadow->signature."' meadow", $available_worker_slots );
    }

    return ($valley_running_worker_count, \%meadow_capacity_limiter_hashed_by_type);
}


=head2 query_worker_statuses

    Arg[1] : Hashref {meadow_type}{meadow_name}{meadow_user}{process_id} => $db_status
    Output : Hashref {meadow_signature}{meadow_status} => [process_ids]

    Description : Queries the available meadows to get the (meadow) status of the given workers

=cut

sub query_worker_statuses {
    my ($self, $db_registered_workers_from_all_meadows_deemed_alive) = @_;

    my %reconciled_worker_statuses  = ();

    foreach my $meadow (@{ $self->get_available_meadow_list }) {    # only go through the available meadows
        my $db_registered_workers_this_meadow   = $db_registered_workers_from_all_meadows_deemed_alive->{$meadow->type}{$meadow->cached_name};
        my $involved_users                      = [keys %$db_registered_workers_this_meadow];

        next unless @$involved_users;

        my %meadow_seen_worker_status           = map { ( $_->[0] => $_->[2] ) } @{ $meadow->status_of_all_our_workers( $involved_users ) };

        my $worker_statuses_of_this_meadow      = $reconciled_worker_statuses{ $meadow->signature } = {};   # manually vivify every Meadow's subhash

        while(my ($meadow_user, $db_user_subhash) = each %$db_registered_workers_this_meadow) { # start the reconciliation from the DB view and check it against Meadow view
            while(my ($worker_pid, $db_worker_status) = each %$db_user_subhash) {
                my $combined_status     = $meadow_seen_worker_status{$worker_pid}
                                       // ( ($db_worker_status=~/^(?:SUBMITTED|DEAD)$/) ? $db_worker_status : 'LOST' );

                push @{ $worker_statuses_of_this_meadow->{ $combined_status } }, $worker_pid;
            }
        }
    }
    return \%reconciled_worker_statuses;
}


sub status_of_all_our_workers_by_meadow_signature {
    my ($self, $reconciled_worker_statuses) = @_;

    my %signature_and_pid_to_worker_status = ();
    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        my $meadow_signature = $meadow->signature;
        $signature_and_pid_to_worker_status{ $meadow_signature } = {};

        my $status_2_pid_list   = $reconciled_worker_statuses->{ $meadow_signature };
        while(my ($status, $pid_list) = each %$status_2_pid_list) {
            $signature_and_pid_to_worker_status{$meadow_signature}{$_} = $status for @$pid_list;
        }
    }
    return \%signature_and_pid_to_worker_status;
}


1;
