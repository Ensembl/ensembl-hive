=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::NakedTable

=head1 SYNOPSIS

=head1 DESCRIPTION

    A data container object that links together an adaptor, a table and a preferred insertion method (insert/insert-ignore/replace).
    This object is generated from specially designed datalow URLs.

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
    my ( $self, $output_ids ) = @_;

        # we have to do this the ugly way
        # because Registry code currently prevents us from passing arguments to adaptors' new() methods
        # (and by caching guarantees there is only one instance of each adaptor per DBAdaptor)
    my $adaptor = $self->adaptor();
    $adaptor->table_name( $self->table_name() );
    $adaptor->insertion_method( $self->insertion_method() );

    $adaptor->store( $output_ids );
}


1;

