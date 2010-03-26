=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LongMult::Start

=head1 DESCRIPTION

'LongMult::Start' is the first step of the LongMult example pipeline that multiplies two long numbers.

It takes apart the second multiplier and creates several 'LongMult::PartMultiply' jobs
that correspond to the different digits of the second multiplier.

It also "flows into" one 'LongMult::AddTogether' job that will wait until 'LongMult::PartMultiply' jobs
complete and will arrive at the final result.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::LongMult::Start;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {   # this time we have nothing to fetch
    my $self = shift @_;

    return 1;
}

sub run {   # following the 'divide and conquer' principle, out job is to create jobs:
    my $self = shift @_;

    my $a_multiplier    = $self->param('a_multiplier')  || die "'a_multiplier' is an obligatory parameter";
    my $b_multiplier    = $self->param('b_multiplier')  || die "'b_multiplier' is an obligatory parameter";

    my %digit_hash = ();
    foreach my $digit (split(//,$b_multiplier)) {
        next if (($digit eq '0') or ($digit eq '1'));
        $digit_hash{$digit}++;
    }

        # output_ids of partial multiplications to be computed:
    my @output_ids = map { { 'a_multiplier' => $a_multiplier, 'digit' => $_ } } keys %digit_hash;

        # store them for future use:
    $self->param('output_ids', \@output_ids);
}

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $output_ids = $self->param('output_ids');

        # "fan out" into branch-2 first
    $self->dataflow_output_id($output_ids, 2);

        # then flow into the branch-1 funnel; input_id would flow into branch_1 by default anyway, but we request it here explicitly:
    $self->dataflow_output_id($self->input_id, 1);

    return 1;
}

1;

