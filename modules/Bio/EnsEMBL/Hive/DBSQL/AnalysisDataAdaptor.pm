=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor

=head1 SYNOPSIS

    $dataDBA = $db_adaptor->get_AnalysisDataAdaptor;

=head1 DESCRIPTION

   analysis_data table holds LONGTEXT data that is currently used as an extension of some fixed-width fields of 'job' table.
   It is no longer general-purpose. Please avoid accessing this table directly or via the adaptor.

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are preceded with a _

=cut


package Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor');


sub default_table_name {
    return 'analysis_data';
}


sub store_if_needed {
    my ($self, $data) = @_;

    my $storable_hash = {'data'=> $data};

    $self->store_or_update_one( $storable_hash  );

    return '_extended_data_id ' . $storable_hash->{'analysis_data_id'};
}

1;
