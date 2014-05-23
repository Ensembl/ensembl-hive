=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::NakedTable

=head1 DESCRIPTION

    A data container object that links together an adaptor, a table and a preferred insertion method (insert/insert-ignore/replace).
    This object is generated from specially designed datalow URLs.

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


package Bio::EnsEMBL::Hive::NakedTable;

use strict;
use warnings;

use base ( 'Bio::EnsEMBL::Hive::Storable' );


sub table_name {
    my $self = shift @_;

    if(@_) {
        $self->{'_table_name'} = shift @_;
    }
    return $self->{'_table_name'};
}


sub insertion_method {
    my $self = shift @_;

    if(@_) {
        $self->{'_insertion_method'} = shift @_;
    }
    return $self->{'_insertion_method'} || 'INSERT_IGNORE';
}


sub url {
    my ($self, $ref_dba) = @_;  # if reference dba is the same as 'our' dba, a shorter url is generated

    my $adaptor = $self->adaptor;
    return ( ($adaptor and $adaptor->db ne ($ref_dba//'') ) ? $adaptor->db->dbc->url : ':///' )
        . '/' . $self->table_name . '?insertion_method=' . $self->insertion_method;
}


sub display_name {
    my ($self, $ref_dba) = @_;  # if reference dba is the same as 'our' dba, a shorter display_name is generated

    my $adaptor = $self->adaptor;
    return ( ($adaptor and $adaptor->db ne ($ref_dba//'') ) ? $adaptor->db->dbc->dbname.'/' : '') . $self->table_name;
}


sub dataflow {
    my ( $self, $output_ids, $emitting_job ) = @_;

        # we have to do this the ugly way
        # because Registry code currently prevents us from passing arguments to adaptors' new() methods
        # (and by caching guarantees there is only one instance of each adaptor per DBAdaptor)
    my $adaptor = $self->adaptor();
    $adaptor->table_name( $self->table_name() );
    $adaptor->insertion_method( $self->insertion_method() );

    my @column_names = keys %{$self->adaptor->column_set};
    my @rows = ();

    foreach my $output_id (@$output_ids) {
        my %row_hash = ();
        foreach my $column (@column_names) {
            $row_hash{ $column } = $emitting_job->_param_possibly_overridden($column, $output_id);
        }
        push @rows, \%row_hash;
    }
    $adaptor->store( \@rows );
}

1;

