=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::PipelineWideParametersAdaptor

=head1 SYNOPSIS

    $pipeline_wide_parameters_adaptor = $db_adaptor->get_PipelineWideParametersAdaptor;

=head1 DESCRIPTION

    This module deals with pipeline_wide_parameters' storage and retrieval, and also stores 'schema_version' for compatibility with Core API

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


package Bio::EnsEMBL::Hive::DBSQL::PipelineWideParametersAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'pipeline_wide_parameters';
}


=head2 fetch_param_hash

    Description: returns the contents of the 'pipeline_wide_parameters' table as a hash

=cut

sub fetch_param_hash {
    my $self = shift @_;

    if( my $collection = Bio::EnsEMBL::Hive::PipelineWideParameters->collection() ) {

        return { map { $_->{'param_name'} => destringify($->{'param_value'}) } $collection->list() };

    } else {    # TODO: to be removed when beekeeper.pl/runWorker.pl become collection-aware

        my $original_value      = $self->fetch_HASHED_FROM_param_name_TO_param_value();
        my %destringified_hash  = map { $_, destringify($original_value->{$_}) } keys %$original_value;

        return \%destringified_hash;
    }
}

1;
