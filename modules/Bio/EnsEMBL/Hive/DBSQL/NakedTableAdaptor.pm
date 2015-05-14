=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor

=head1 SYNOPSIS

    $naked_table_adaptor = $dba->get_NakedTableAdaptor;
    $naked_table_adaptor = $naked_table->adaptor;

=head1 DESCRIPTION

    This module together with its data container are used to enable dataflow into arbitrary tables (rather than just 'job' table).
    Due to the implementation of EnsEMBL Registry code, NakedTable objects know *where* to dataflow, and NakedTableAdaptor knows *how* to dataflow.

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


package Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::DBSQL::BaseAdaptor');


sub slicer {    # take a slice of the hashref (if only we could inline in Perl!)
    my ($self, $hashref, $fields) = @_;

    return [ @$hashref{@$fields} ];
}


sub objectify {    # pretend the hashref becomes an object (if only we could inline in Perl!)
    return pop @_;
}


sub mark_stored {
    my ($self, $hashref, $dbID) = @_;

    if(my $autoinc_id = $self->autoinc_id()) {
        $hashref->{$autoinc_id} = $dbID;
    }
}


sub keys_to_columns {
    my ($self, $hashref) = @_;

    my $sorted_keys = [ sort keys %$hashref ];

    return ( $sorted_keys, join(', ', @$sorted_keys) );
}

1;

