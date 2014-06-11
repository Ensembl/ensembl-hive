=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor

=head1 SYNOPSIS

    $dba->get_MetaAdaptor->store( \@rows );

=head1 DESCRIPTION

    This is currently an "objectless" adaptor for storing and fetching Hive-specific metadata

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


package Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::MetaParameters;

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'hive_meta';
}


sub get_value_by_key {
    my ($self, $meta_key) = @_;

    if( my $collection = Bio::EnsEMBL::Hive::MetaParameters->collection() ) {

        my $hash = $collection->find_one_by( 'meta_key', $meta_key );
        return $hash && $hash->{'meta_value'};

    } else {    # TODO: to be removed when beekeeper.pl/runWorker.pl become collection-aware

        my $pair = $self->fetch_by_meta_key( $meta_key );
        return $pair && $pair->{'meta_value'};
    }
}

1;

