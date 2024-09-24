=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Semaphore

=head1 DESCRIPTION

    A Semaphore object is our main instrument of fine-grained job control.
    It is controlled (blocked) by a group of "fan" jobs and remote semaphores and has
    either a dependent local job or a dependent remote semaphore
    that will be unblocked when both local_jobs_counter and remote_jobs_counter reach zeros.

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Semaphore;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::TheApiary;

use base ( 'Bio::EnsEMBL::Hive::Storable' );


=head1 AUTOLOADED

    dependent_job_id / dependent_job

=cut

# ---------------------------------------------------------------------------

sub local_jobs_counter {
    my $self = shift;
    $self->{'_local_jobs_counter'} = shift if(@_);
    return $self->{'_local_jobs_counter'};
}


sub remote_jobs_counter {
    my $self = shift;
    $self->{'_remote_jobs_counter'} = shift if(@_);
    return $self->{'_remote_jobs_counter'};
}


sub dependent_semaphore_url {
    my $self = shift;
    $self->{'_dependent_semaphore_url'} = shift if(@_);
    return $self->{'_dependent_semaphore_url'};
}

# ---------------------------------------------------------------------------

sub dependent_semaphore {
    my $self = shift @_;

    if(my $dependent_semaphore_url = $self->dependent_semaphore_url) {
        return Bio::EnsEMBL::Hive::TheApiary->find_by_url( $dependent_semaphore_url );
    } else {
        return undef;
    }
}


sub ultimate_dependent_job {
    my $self = shift @_;

    return $self->dependent_job || $self->dependent_semaphore->ultimate_dependent_job;
}


sub url_query_params {
     my ($self) = @_;

     return {
        'semaphore_id'  => $self->dbID,
     };
}

# ---------------------------------------------------------------------------

sub check_if_ripe {
    my $self    = shift @_;

    $self->adaptor->refresh( $self );

    return ($self->local_jobs_counter + $self->remote_jobs_counter <= 0);
}


sub increase_by {
    my $self                            = shift @_;
    my $blocking_objects_or_local_delta = shift @_;
    my $sign                            = shift @_ || 1;

    if(my $semaphore_adaptor = $self->adaptor) {

        my ($local_delta, $remote_delta)    = ref($blocking_objects_or_local_delta)
                                                ? $self->count_local_and_remote_objects( $blocking_objects_or_local_delta )
                                                : ($blocking_objects_or_local_delta,0);
        my $semaphore_id                    = $self->dbID;

        if($local_delta) {
            $semaphore_adaptor->increment_column_by_inc_and_id( 'local_jobs_counter', $sign * $local_delta, $semaphore_id );
        }
        if($remote_delta) {
            $semaphore_adaptor->increment_column_by_inc_and_id( 'remote_jobs_counter', $sign * $remote_delta, $semaphore_id );
        }

    } else {
        die "Local semaphore objects are not yet supported";    # but they could be, eventually!
    }
}


sub reblock_by {
    my $self                            = shift @_;
    my $blocking_objects_or_local_delta = shift @_;

    my $was_ripe            = $self->check_if_ripe;

    $self->increase_by( $blocking_objects_or_local_delta );

    if( $was_ripe ) {

        if(my $dependent_job = $self->dependent_job) {

            if(my $dependent_job_adaptor = $dependent_job->adaptor) {
                $dependent_job_adaptor->semaphore_job_by_id( $dependent_job->dbID );
            } else {
                die "Dependent job is expected to have a working JobAdaptor";
            }

        } elsif(my $dependent_semaphore = $self->dependent_semaphore) {

            $dependent_semaphore->reblock( [ $self ] ); # recursion

        } else {
            warn "The semaphore is not blocking anything, possibly the end of execution.\n";
        }
    }
}


sub fetch_my_raw_accu_data {
    my $self    = shift @_;

    return $self->adaptor->db->get_AccumulatorAdaptor->fetch_all_by_receiving_semaphore_id( $self->dbID );
}


sub fetch_my_local_controlling_jobs {
    my $self    = shift @_;

    return $self->adaptor->db->get_AnalysisJobAdaptor->fetch_all_by_controlled_semaphore_id( $self->dbID );
}


sub release_if_ripe {
    my $self    = shift @_;

    if( $self->check_if_ripe ) {

        if(my $dependent_job = $self->dependent_job) {

            if(my $dependent_job_adaptor = $dependent_job->adaptor) {
                $dependent_job_adaptor->unsemaphore_job_by_id( $dependent_job->dbID );
            } else {
                die "Dependent job is expected to have a working JobAdaptor";
            }

        } elsif(my $dependent_semaphore = $self->dependent_semaphore) {

            my $dependent_semaphore_adaptor = $dependent_semaphore->adaptor;
            my $ocean_separated             = $dependent_semaphore_adaptor->db ne $self->adaptor->db;

                # pass the accumulated data here:
            if(my $raw_accu_data = $self->fetch_my_raw_accu_data) {
                foreach my $vector ( @$raw_accu_data ) {
                    $vector->{'receiving_semaphore_id'} = $dependent_semaphore->dbID;   # set the new consumer
                    $vector->{'sending_job_id'}         = undef if($ocean_separated);   # dissociate from the sending job as it was local
                }
                $dependent_semaphore_adaptor->db->get_AccumulatorAdaptor->store( $raw_accu_data );
            }

            $dependent_semaphore_adaptor->increment_column_by_inc_and_id( 'remote_jobs_counter', -1, $dependent_semaphore->dbID );

            $dependent_semaphore->release_if_ripe();    # recursion

        } else {
            warn "The semaphore is not blocking anything, possibly the end of execution.\n";
        }
    }
}


sub decrease_by {
    my $self                            = shift @_;
    my $blocking_objects_or_local_delta = shift @_;

    $self->increase_by( $blocking_objects_or_local_delta, -1);

    $self->release_if_ripe();
}

1;
