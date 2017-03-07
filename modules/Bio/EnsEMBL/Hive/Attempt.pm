=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Attempt

=head1 DESCRIPTION

    An object to describe an attempt of a job.
    It is stored in its own table (attempt) indexed by a dbID, and is thus Storable

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


package Bio::EnsEMBL::Hive::Attempt;

use strict;
use warnings;

use base ( 'Bio::EnsEMBL::Hive::Storable' );


# ----------------------------- Cacheable implementation -----------------------------------

sub unikey {
    return [ 'dbID' ];
}


# --------------------------------- Getter / Setters ---------------------------------------

sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    return $self->{'_status'} || 'INITIALIZATION';
}


sub when_initialized {
    my $self = shift;
    $self->{'_when_initialized'} = shift if(@_);
    return $self->{'_when_initialized'};
}

sub when_updated {
    my $self = shift;
    $self->{'_when_updated'} = shift if(@_);
    return $self->{'_when_updated'};
}

sub when_ended {
    my $self = shift;
    $self->{'_when_ended'} = shift if(@_);
    return $self->{'_when_ended'};
}

sub runtime_msec {
    my $self = shift;
    $self->{'_runtime_msec'} = shift if(@_);
    return $self->{'_runtime_msec'};
}

sub is_success {
    my $self = shift;
    $self->{'_is_success'} = shift if(@_);
    return $self->{'_is_success'};
}

sub query_count {
    my $self = shift;
    $self->{'_query_count'} = shift if(@_);
    return $self->{'_query_count'};
}

sub stdout_file {
  my $self = shift;
  $self->{'_stdout_file'} = shift if(@_);
  return $self->{'_stdout_file'};
}

sub stderr_file {
  my $self = shift;
  $self->{'_stderr_file'} = shift if(@_);
  return $self->{'_stderr_file'};
}



# --------------------------------- Compound methods ---------------------------------------

sub toString {
    my $self = shift @_;

    my $attempt_count = $self->job->attempt_count;
    my $suffix = 'th';
       $suffix = 'st' if ($attempt_count % 10 == 1) && ($attempt_count != 11);
       $suffix = 'nd' if ($attempt_count % 10 == 2) && ($attempt_count != 12);
       $suffix = 'rd' if ($attempt_count % 10 == 3) && ($attempt_count != 13);
    return $attempt_count.$suffix.' attempt of '.$self->job->toString;
}


# -------------------------------- Convenient methods --------------------------------------

=head2 set_and_update_status

  Example     : $attempt->set_and_update_status('WRITE_OUTPUT');
  Description : Sets the status of the attempt (within the job's life-cycle) and updates
                the database accordingly.
  Returntype  : none
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub set_and_update_status {
    my ($self, $status) = @_;

    $self->status($status);

    if(my $adaptor = $self->adaptor) {
        $adaptor->check_in_attempt($self);
    }
}


1;

