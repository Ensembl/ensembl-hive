=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Valley

=head1 DESCRIPTION

    A Valley represents a collection of available Meadows.

    Certain methods fit better with the concept of Valley -
    such as identifying all dead workers, or killing a particular one given worker_id.

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


package Bio::EnsEMBL::Hive::Valley;

use strict;
use warnings;
use Sys::Hostname;
use Bio::EnsEMBL::Hive::Utils ('find_submodules');
use Bio::EnsEMBL::Hive::Limiter;

use base ('Bio::EnsEMBL::Hive::Configurable');


sub meadow_class_path {

    return 'Bio::EnsEMBL::Hive::Meadow';
}


sub new {
    my ($class, $config, $default_meadow_type, $pipeline_name) = @_;

    my $self = bless {}, $class;

    $self->config( $config );
    $self->context( [ 'Valley' ] );

    my $amh = $self->available_meadow_hash( {} );

        # make sure modules are loaded and available ones are checked prior to setting the current one
    foreach my $meadow_class (@{ find_submodules( $self->meadow_class_path ) }) {
        eval "require $meadow_class";
        if( $meadow_class->name ) {
            my $meadow_object            = $meadow_class->new( $config );

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

    my ($meadow_type, $meadow_name, $pid);
    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        eval {
            $pid         = $meadow->get_current_worker_process_id();
            $meadow_type = $meadow->type();
            $meadow_name = $meadow->cached_name();
        };
        unless($@) {
            last;
        }
    }
    unless($pid) {
        die "Could not determine the Meadow, please investigate";
    }

    my $exechost = hostname();

    return ($meadow_type, $meadow_name, $pid, $exechost);
}


sub get_pending_worker_counts_by_meadow_type_rc_name {
    my $self = shift @_;

    my %pending_counts = ();
    my $total_pending_all_meadows = 0;

    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        my ($pending_this_meadow_by_rc_name, $total_pending_this_meadow) = ($meadow->count_pending_workers_by_rc_name());
        $pending_counts{ $meadow->type } = $pending_this_meadow_by_rc_name;
        $total_pending_all_meadows += $total_pending_this_meadow;
    }

    return (\%pending_counts, $total_pending_all_meadows);
}


sub get_meadow_capacity_hash_by_meadow_type {
    my $self = shift @_;

    my %meadow_capacity_hash = ();

    foreach my $meadow (@{ $self->get_available_meadow_list }) {

        my $available_worker_slots = defined($meadow->config_get('TotalRunningWorkersMax'))
            ? $meadow->config_get('TotalRunningWorkersMax') - $meadow->count_running_workers
            : undef;

            # so the hash will contain limiters for every meadow_type, but not all of them active:
        $meadow_capacity_hash{ $meadow->type } = Bio::EnsEMBL::Hive::Limiter->new( "Number of workers in '".$meadow->signature."' meadow", $available_worker_slots );
    }

    return \%meadow_capacity_hash;
}


sub count_running_workers {     # just an aggregator
    my $self = shift @_;

    my $valley_running_workers = 0;

    foreach my $meadow (@{ $self->get_available_meadow_list }) {
        $valley_running_workers += $meadow->count_running_workers;
    }

    return $valley_running_workers;
}


1;

