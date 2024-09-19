=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::NakedTable

=head1 DESCRIPTION

    A data container object that links together an adaptor, a table and a preferred insertion method (insert/insert-ignore/replace).
    This object is generated from specially designed datalow URLs.

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

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


sub unikey {    # override the default from Cacheable parent
    return [ 'table_name' ];
}


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


sub url_query_params {
     my ($self) = @_;

     return {   # direct access to the actual (possibly missing) values
        'table_name'            => $self->table_name,
        'insertion_method'      => $self->{'_insertion_method'},
     };
}


sub display_name {
    my ($self) = @_;
    return $self->table_name;
}


sub dataflow {
    my ( $self, $output_ids, $emitting_job ) = @_;

    my $adaptor      = $self->adaptor();
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


sub toString {
    my $self = shift @_;

    return 'NakedTable('.$self->table_name.')';
}

1;

