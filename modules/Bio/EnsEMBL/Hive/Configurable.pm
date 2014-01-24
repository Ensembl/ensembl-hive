=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Configurable

=head1 DESCRIPTION

    A base class for objects that we want to be configurable in the following sense:
        1) have a pointer to the $config
        2) know their context
        3) automatically apply that context when getting and setting

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


package Bio::EnsEMBL::Hive::Configurable;

use strict;
use warnings;


sub config {
    my $self = shift @_;

    if(@_) {
        $self->{'_config'} = shift @_;
    }
    return $self->{'_config'};
}


sub context {
    my $self = shift @_;

    if(@_) {
        $self->{'_context'} = shift @_;
    }
    return $self->{'_context'};
}


sub config_get {
    my $self = shift @_;

    return $self->config->get( @{$self->context}, @_ );
}


sub config_set {
    my $self = shift @_;

    return $self->config->set( @{$self->context}, @_ );
}


1;
