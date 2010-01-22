=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether

=head1 DESCRIPTION

'LongMult::AddTogether' is the final step of the pipeline that, naturally, adds the products together
and stores the result in 'final_result' database table;

=cut

package Bio::EnsEMBL::Hive::RunnableDB::LongMult::AddTogether;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {   # fetch all the (relevant) precomputed products
    my $self = shift @_;

    my $a_multiplier = $self->param('a_multiplier') || die "'a_multiplier' is an obligatory parameter";
    my %product_pair = ();

    my $sql = "SELECT digit, result FROM intermediate_result WHERE a_multiplier = ?";
    my $sth = $self->db->dbc()->prepare($sql);
    $sth->execute($a_multiplier);
    while (my ($digit, $result)=$sth->fetchrow_array()) {
        $product_pair{$digit} = $result;
    }
    $sth->finish();
    $product_pair{1} = $a_multiplier;
    $product_pair{0} = 0;

    $self->param('product_pair', \%product_pair);

    return 1;
}

sub run {   # call the function that will compute the stuff
    my $self = shift @_;

    my $b_multiplier = $self->param('b_multiplier') || die "'b_multiplier' is an obligatory parameter";
    my $product_pair = $self->param('product_pair');

    $self->param('result', add_together($b_multiplier, $product_pair));
}

sub write_output {  # store the final result
    my $self = shift @_;

    my $sql = "REPLACE INTO final_result (a_multiplier, b_multiplier, result) VALUES (?, ?, ?) ";
    my $sth = $self->db->dbc->prepare($sql);
    $sth->execute(
        $self->param('a_multiplier'),
        $self->param('b_multiplier'),
        $self->param('result')
    );
    $sth->finish();

    return 1;
}

######################### do the maths ###############

sub add_together {
    my ($b_multiplier, $product_pair) = @_;

    my @accu  = ();

    my @b_digits = reverse split(//, $b_multiplier);
    foreach my $b_index (0..(@b_digits-1)) {
        my $b_digit = $b_digits[$b_index];
        my $product = $product_pair->{$b_digit};

        my @p_digits = reverse split(//, $product);
        foreach my $p_index (0..(@p_digits-1)) {
            $accu[$b_index+$p_index] += $p_digits[$p_index];
        }
    }

    foreach my $a_index (0..(@accu-1)) {
        my $a_digit       = $accu[$a_index];
        my $carry         = int($a_digit/10);
        $accu[$a_index]   = $a_digit % 10;
        $accu[$a_index+1] += $carry;
    }

        # get rid of the leading zero
    unless($accu[@accu-1]) {
        pop @accu;
    }

    return join('', reverse @accu);
}

1;

