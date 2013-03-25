
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck \
                    -db_conn mysql://ensro@compara1/mm14_compara_homology_71 \
                    -inputquery 'SELECT * FROM member WHERE genome_db_id = 90 AND source_name = "ENSEMBLGENE"'
                    -expected_size '>= 20000'

=head1 DESCRIPTION

This is a generic RunnableDB module for testing the size of the resultset of any SQL query.

The query is passed by the parameter 'inputquery' (param substituted)
The expected size is passed by the parameter 'expected_size' as a string "CONDITION VALUE" (CONDITION defaults to equality, VALUE defaults to 0).
Currently, CONDITION is one of: = == < <= > >= <> !=

=cut

package Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck;

use strict;

use base ('Bio::EnsEMBL::Hive::Process');


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  
=cut

sub fetch_input {
    my $self = shift @_;

    $self->param_required('inputquery');
    
    my $expected_size = $self->param('expected_size');
    unless ($expected_size =~ /^\s*(=|==|>|>=|<|<=|<>|!=|)\s*(\d*)\s*$/) {
        die "Cannot interpret the 'expected_size' parameter: '$expected_size'";
    }
    $self->param('logical_test', $1 || '=');
    $self->param('reference_number', $2 || '0');
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).


=cut

sub run {
    my $self = shift @_;

    my $reference_number    = $self->param('reference_number');
    my $logical_test        = $self->param('logical_test');
    warn "logical test: '$logical_test', $reference_number: '$reference_number'" if ($self->debug());

    my $maxrow = $reference_number;
    $maxrow++ if grep {$_ eq $logical_test} qw(= == > <= <> !=);

    my $nrow = $self->_get_rowcount_bound($maxrow);

    if ($logical_test eq '=' or $logical_test eq '==') {
        die "At least $nrow rows, different than $reference_number" if $nrow != $reference_number;

    } elsif ($logical_test eq '<' or $logical_test eq '<=') {
        die "At least $nrow rows, more then the maximum authorized value" if $nrow >= $maxrow;

    } elsif ($logical_test eq '>' or $logical_test eq '>=') {
        die "$nrow rows returned in total, less than the minimum authorized value ($maxrow)" if $nrow < $maxrow;

    } elsif ($logical_test eq '<>' or $logical_test eq '!=') {
        die "$nrow rows returned in total, exactly the non-authorized value ($reference_number)" if $nrow == $reference_number;

    } else {
        die "This should not happen. A logical test is not checked";
    }

    warn "$nrow rows returned: the test is successful" if ($self->debug());
}


=head2 _get_rowcount_bound

    Description: Tries to fetch at least $maxrow rows from the database. Returns the actual number of fetched rows.

    param('inputquery'); SQL query (against the production database by default) : 'inputquery' => 'SELECT object_id FROM object WHERE x=y'

=cut

sub _get_rowcount_bound {
    my $self    = shift @_;
    my $maxrow  = shift @_;

    my $inputquery  = $self->param_required('inputquery');
    warn "Testing at least '$maxrow' rows of the input query: '$inputquery'" if ($self->debug());
    $inputquery .= " LIMIT $maxrow" unless $inputquery =~ /LIMIT/i;

    my $sth = $self->data_dbc()->prepare($inputquery);
    $sth->{mysql_use_result} = 1 if $self->data_dbc->driver eq 'mysql';
    $sth->execute();

    my $nrow = 0;
    while (defined $sth->fetchrow_arrayref()) {
        $nrow++;
    }
    $sth->finish;

    return $nrow;
}

1;
