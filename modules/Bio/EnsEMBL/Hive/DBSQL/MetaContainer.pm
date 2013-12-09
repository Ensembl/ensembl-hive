=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::MetaContainer

=head1 SYNOPSIS

    $meta_container = $db_adaptor->get_MetaContainer;

=head1 DESCRIPTION

    This module deals with pipeline_wide_parameters' storage and retrieval, and also stores 'schema_version' for compatibility with Core API

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


package Bio::EnsEMBL::Hive::DBSQL::MetaContainer;

use strict;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor', 'Bio::EnsEMBL::DBSQL::BaseMetaContainer');


sub default_table_name {
    return 'meta';
}


sub store_pair {
    my ($self, $meta_key, $meta_value) = @_;

    return $self->store( { 'meta_key' => $meta_key, 'meta_value' => stringify( $meta_value ), 'species_id' => undef } );
}


=head2 get_param_hash

    Description: returns the content of the 'meta' table as a hash

=cut

sub get_param_hash {
    my $self = shift @_;

    my $original_value      = $self->fetch_all_HASHED_FROM_meta_key_TO_meta_value();
    my %destringified_hash  = map { $_, destringify($original_value->{$_}[0]) } keys %$original_value;

    return \%destringified_hash;
}

1;
