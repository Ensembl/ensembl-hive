=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Role

=head1 DESCRIPTION

    Role is a state of a Worker while performing jobs of a particular Analysis.

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::Role;

use strict;
use warnings;

use base ( 'Bio::EnsEMBL::Hive::Storable' );


=head1 AUTOLOADED

    worker_id / worker
    analysis_id / analysis

=cut


sub when_started {
    my $self = shift;
    $self->{'_when_started'} = shift if(@_);
    return $self->{'_when_started'};
}


sub when_finished {
    my $self = shift;
    $self->{'_when_finished'} = shift if(@_);
    return $self->{'_when_finished'};
}


sub attempted_jobs {
    my $self = shift;
    $self->{'_attempted_jobs'} = shift if(@_);
    return $self->{'_attempted_jobs'} || 0;
}


sub done_jobs {
    my $self = shift;
    $self->{'_done_jobs'} = shift if(@_);
    return $self->{'_done_jobs'} || 0;
}


sub register_attempt {
    my $self    = shift;
    my $success = shift;

    $self->{'_attempted_jobs'}++;
    $self->{'_done_jobs'}     += $success;

    if( my $adaptor = $self->adaptor ) {
        $adaptor->update_attempted_jobs_AND_done_jobs( $self );
    }
}

1;
