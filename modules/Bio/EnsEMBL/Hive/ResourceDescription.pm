=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::ResourceDescription

=head1 DESCRIPTION

    A data container object (the only methods are getters/setters) that corresponds to a row in 'resource_description' table:

    CREATE TABLE resource_description (
        resource_class_id     int(10) unsigned NOT NULL,
        meadow_type           varchar(40) NOT NULL,
        submission_cmd_args     VARCHAR(255) NOT NULL DEFAULT '',
        worker_cmd_args         VARCHAR(255) NOT NULL DEFAULT '',

        PRIMARY KEY(resource_class_id, meadow_type)
    ) ENGINE=InnoDB;

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::ResourceDescription;

use strict;
use warnings;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );


sub unikey {    # override the default from Cacheable parent
    return [ 'resource_class', 'meadow_type' ];
}


=head1 AUTOLOADED

    resource_class_id / resource_class

=cut


sub meadow_type {
    my $self = shift @_;

    if(@_) {
        $self->{'_meadow_type'} = shift @_;
    }
    return $self->{'_meadow_type'};
}


sub submission_cmd_args {
    my $self = shift @_;

    if(@_) {
        $self->{'_submission_cmd_args'} = shift @_;
    }
    return $self->{'_submission_cmd_args'} || '';
}


sub worker_cmd_args {
    my $self = shift @_;

    if(@_) {
        $self->{'_worker_cmd_args'} = shift @_;
    }
    return $self->{'_worker_cmd_args'} || '';
}


sub toString {
    my $self = shift @_;

    return 'ResourceDescription: ('.$self->resource_class->name.', '.$self->meadow_type.')->("'.$self->submission_cmd_args.'", "'.$self->worker_cmd_args.'")';
}

1;

