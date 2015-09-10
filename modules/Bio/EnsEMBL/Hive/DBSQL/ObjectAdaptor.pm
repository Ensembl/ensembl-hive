=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor

=head1 SYNOPSIS

    $object_adaptor = $dba->get_SpecificObjectAdaptor;
    $object_adaptor = $specific_object->adaptor;

=head1 DESCRIPTION

    This module defines a parent class for all specific object adaptors.
    It is not supposed to be instantiated directly.

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


package Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor');


sub object_class {
    die "Please define object_class() in your specific adaptor class to return the class name of your intended object";
}


sub slicer {    # take a slice of the object (if only we could inline in Perl!)
    my ($self, $object, $fields) = @_;

    my $autoinc_id      = $self->autoinc_id();
    my $overflow_limit  = $self->overflow_limit();

    return [ map { ($_ eq $autoinc_id)
                    ? $object->dbID()
                    : eval { my $value  = $object->$_();
                             my $ol     = $overflow_limit->{$_};
                             (defined($ol) and length($value)>$ol)
                                ? $self->db->get_AnalysisDataAdaptor()->store_if_needed( $value )
                                : $value
                      }
                 } @$fields ];
}


sub objectify { # turn the hashref into an object (if only we could inline in Perl!)
    my ($self, $hashref) = @_;

    my $autoinc_id = $self->autoinc_id();

    my $object = $self->object_class()->new( 'adaptor' => $self, map { ( ($_ eq $autoinc_id) ? 'dbID' : $_ ) => $hashref->{$_} } keys %$hashref );
    $object->hive_pipeline($self->db->hive_pipeline) if $self->db->hive_pipeline and $object->can('hive_pipeline');
    return $object;
}


sub mark_stored {
    my ($self, $object, $dbID) = @_;

    if($self->autoinc_id()) {
        $object->dbID($dbID);
    }
    $object->adaptor($self);
}


sub keys_to_columns {
    my ($self, $object) = @_;

    my $autoinc_id  = $self->autoinc_id();
    my $sorted_keys = [ sort grep { ($_ ne $autoinc_id) and defined($object->$_()) } keys %{ $self->column_set() } ];

    return ( $sorted_keys, join(', ', @$sorted_keys) );
}



1;

