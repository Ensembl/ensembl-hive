=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::ResourceClass

=head1 DESCRIPTION

    A data container object (the only methods are getters/setters) that corresponds to a row in 'resource_class' table:

    CREATE TABLE resource_class (
        resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,     # unique internal id
        name                varchar(40) NOT NULL,

        PRIMARY KEY(resource_class_id)
    );

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::ResourceClass;

use strict;

use Bio::EnsEMBL::Utils::Argument ('rearrange');

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );
 

sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

    my ($name) =
         rearrange([qw(name) ], @_);

    $self->name($name) if($name);

    return $self;
}


sub name {
    my $self = shift @_;

    if(@_) {
        $self->{'_name'} = shift @_;
    }
    return $self->{'_name'};
}


sub toString {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(dbID name) ));
}

1;

