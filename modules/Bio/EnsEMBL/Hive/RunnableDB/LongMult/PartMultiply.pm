=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply

=head1 DESCRIPTION

'LongMult::PartMultiply' has a separate task of multiplying 'a_multiplier' by the given 'digit',
then it stores the result into the 'intermetiate_result' database table.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {   # again, nothing to fetch
    my $self = shift @_;

    return 1;
}

sub run {   # call the recursive function that will compute the stuff
    my $self = shift @_;

    my $a_multiplier = $self->param('a_multiplier') || die "'a_multiplier' is an obligatory parameter";
    my $digit        = $self->param('digit')        || die "'digit' is an obligatory parameter";

    $self->param('result', rec_multiply($a_multiplier, $digit, 0) || 0);
}

sub write_output {  # but this time we have something to store
    my $self = shift @_;

    my $sql = "REPLACE INTO intermediate_result (a_multiplier, digit, result) VALUES (?, ?, ?) ";
    my $sth = $self->db->dbc->prepare($sql);
    $sth->execute(
        $self->param('a_multiplier'),
        $self->param('digit'),
        $self->param('result')
    );

    return 1;
}

######################### long multiplication ###############

sub rec_multiply {
    my ($a_multiplier, $digit, $carry) = @_;

        # recursion end:
    unless($a_multiplier) {
        return ($carry || '');
    }

        # recursion step:
    if($a_multiplier=~/^(\d*)(\d)$/) {
        my ($prefix, $last_digit) = ($1, $2);

        my $this_product = $last_digit*$digit+$carry;
        my $this_result  = $this_product % 10;
        my $this_carry   = int($this_product / 10);

        return rec_multiply($prefix, $digit, $this_carry).$this_result;
    } else {
        die "'a_multiplier' has to be a decimal number";
    }
}

1;

