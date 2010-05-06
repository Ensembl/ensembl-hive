
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply

=head1 SYNOPSIS

Please refer to Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf pipeline configuration file
to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

'LongMult::PartMultiply' has a separate task of multiplying 'a_multiplier' by the given 'digit',
then it stores the result into the 'intermetiate_result' database table.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::LongMult::PartMultiply;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here we have nothing to fetch.

=cut

sub fetch_input {
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  The only thing we do here is make a call to the recursive function that will compute the product.

    param('a_multiplier'):  The first long number (a string of digits - doesn't have to fit a register).

    param('digit'):         A decimal digit that is a part of the second multiplier.

=cut

sub run {   # call the recursive function that will compute the stuff
    my $self = shift @_;

    my $a_multiplier = $self->param('a_multiplier') || die "'a_multiplier' is an obligatory parameter";
    my $digit        = $self->param('digit')        || die "'digit' is an obligatory parameter";

    $self->param('result', _rec_multiply($a_multiplier, $digit, 0) || 0);
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we store the product in 'intermediate_result' table.

=cut

sub write_output {  # but this time we have something to store
    my $self = shift @_;

    my $sql = "REPLACE INTO intermediate_result (a_multiplier, digit, result) VALUES (?, ?, ?) ";
    my $sth = $self->db->dbc->prepare($sql);
    $sth->execute(
        $self->param('a_multiplier'),
        $self->param('digit'),
        $self->param('result')
    );
}

=head2 _rec_multiply
    
    Description: this is a private function (not a method) that performs recursive multiplication of a long number by a digit with a carry.

=cut

sub _rec_multiply {
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

        return _rec_multiply($prefix, $digit, $this_carry).$this_result;
    } else {
        die "'a_multiplier' has to be a decimal number";
    }
}

1;

