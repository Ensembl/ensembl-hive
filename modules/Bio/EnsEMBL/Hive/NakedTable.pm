=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::NakedTable

=head1 DESCRIPTION

    A data container object that links together an adaptor, a table and a preferred insertion method (insert/insert-ignore/replace).
    This object is generated from specially designed datalow URLs.

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


package Bio::EnsEMBL::Hive::NakedTable;

use strict;
use Scalar::Util ('weaken');

use Bio::EnsEMBL::Utils::Argument ('rearrange');

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my ($adaptor, $table_name, $insertion_method) = 
         rearrange([qw(adaptor table_name insertion_method) ], @_);

    $self->adaptor($adaptor)                    if(defined($adaptor));
    $self->table_name($table_name)              if(defined($table_name));
    $self->insertion_method($insertion_method)  if(defined($insertion_method));

    return $self;
}


sub adaptor {
    my $self = shift @_;

    if(@_) {
        $self->{'_adaptor'} = shift @_;
        weaken $self->{'_adaptor'};
    }

    return $self->{'_adaptor'};
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

sub url {
    my $self    = shift @_;
    my $ref_dba = shift @_;     # if reference dba is the same as 'our' dba, a shorter url can be generated

    if(my $adaptor = $self->adaptor) {
        my $conn_prefix = ($adaptor->db == $ref_dba) ? ':///' : $adaptor->db->dbc->url();
        return $conn_prefix .'/'. $self->table_name() . '?insertion_method=' . $self->insertion_method();
    } else {
        return;
    }
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

