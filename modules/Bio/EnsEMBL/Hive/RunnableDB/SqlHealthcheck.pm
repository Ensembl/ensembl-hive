=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck \
                    -db_conn mysql://ensro@compara1/mm14_compara_homology_71 \
                    -description 'We expect at least 20,000 human genes' \
                    -query 'SELECT * FROM member WHERE genome_db_id = 90 AND source_name = "ENSEMBLGENE"' \
                    -expected_size '>= 20000'

=head1 DESCRIPTION

    This is a generic RunnableDB module for testing the size of the resultset of any SQL query.

    The query is passed by the parameter 'inputquery' (param substituted)
    The expected size is passed by the parameter 'expected_size' as a string "CONDITION VALUE" (CONDITION defaults to equality, VALUE defaults to 0).
    Currently, CONDITION is one of: = == < <= > >= <> !=

    TODO: implement a "expected_value" test

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


package Bio::EnsEMBL::Hive::RunnableDB::SqlHealthcheck;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');


sub param_defaults {
    return {
        description => '/no description/',
    }
}



=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  
=cut

sub fetch_input {
    my $self = shift @_;

    $self->param('inputquery') && warn "'inputquery' is deprecated in SqlHealthcheck. Use 'query' instead\n";
    
    my $test = {
        description => $self->param('description'),
        query => $self->param('inputquery') || $self->param_required('query'),
        expected_size => $self->param('expected_size'),
    };

    $self->param('tests', [$test]);
    $self->_validate_tests;
}


=head2 _validate_tests

    Description : Checks that the tests are properly defined, and parses the "expected_size"

=cut

sub _validate_tests {
    my $self = shift @_;

    foreach my $test (@{$self->param('tests')}) {
        die "The SQL query must be provided" unless $test->{query};
        die "The description must be provided" unless $test->{description};
        $test->{subst_query} = $self->param_substitute($test->{query});
        my $expected_size = $self->param_substitute($test->{expected_size} || '');
        unless ($expected_size =~ /^\s*(=|==|>|>=|<|<=|<>|!=|)\s*(\d*)\s*$/) {
            die "Cannot interpret the 'expected_size' parameter: '$expected_size'";
        }
        $test->{logical_test} = $1 || '=';
        $test->{reference_size} = $2 || '0';
    }
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process
                  Iterate through the tests and run them all. Report the failed tests at the end

=cut

sub run {
    my $self = shift @_;

    my @failures = ();
    foreach my $test (@{$self->param('tests')}) {
        push @failures, $test unless $self->_run_test($test);
    }
    die "The following tests have failed:\n".join('', map {sprintf(" - %s\n   > %s\n", $_->{description}, $_->{subst_query})} @failures) if @failures;
}


=head2 _run_test

    Description : Runs a single test, defined in a hash with the following keys:
                   description, query, reference_size, logical_test

=cut

sub _run_test {
    my $self = shift @_;
    my $test = shift @_;

    my $description = $test->{description};
    my $query = $test->{subst_query};
    my $reference_size = $test->{reference_size};
    my $logical_test = $test->{logical_test};

    # Final semicolons are removed if present
    if ($query =~ /(;\s*$)/) {
        $query =~ s/$1//;
    }

    print "Test description: $description\n";
    print "Checking whether the number of rows $logical_test $reference_size\n";

    # This could benefit from 'switch' once we move to a more recent version of Perl
    my $maxrow = $reference_size;
    $maxrow++ if grep {$_ eq $logical_test} qw(= == > <= <> !=);

    $query .= " LIMIT $maxrow" unless $query =~ /LIMIT/i;
    print "Query: $query\n";

    my $sth = $self->data_dbc()->prepare($query);
    $sth->{mysql_use_result} = 1 if $self->data_dbc->driver eq 'mysql';
    $sth->execute();

    my $nrow = 0;
    while (defined $sth->fetchrow_arrayref()) {
        $nrow++;
    }
    $sth->finish;

    print "$nrow rows returned".($nrow == $maxrow ? " (test aborted, there could be more rows)" : "")."\n";

    # This could benefit from 'switch' once we move to a more recent version of Perl
    my $success = 0;
    if ($logical_test eq '=' or $logical_test eq '==') {
        $success = 1 if $nrow == $reference_size;

    } elsif ($logical_test eq '<' or $logical_test eq '<=') {
        $success = 1 if $nrow < $maxrow;

    } elsif ($logical_test eq '>' or $logical_test eq '>=') {
        $success = 1 if $nrow >= $maxrow;

   } elsif ($logical_test eq '<>' or $logical_test eq '!=') {
        $success = 1 if $nrow != $reference_size;

    } else {
        die "This should not happen. A logical test is not checked";
    }
    warn $success ? "Success\n\n" : "Failure\n\n";
    return $success;
}


1;
