=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LongMult::SemaStart

=head1 DESCRIPTION

'LongMult::SemaStart' is an alternative first step of the LongMult example pipeline that multiplies two long numbers.

In the same manner as 'LongMult::Start', it takes apart the second multiplier and creates several 'LongMult::PartMultiply' jobs
that correspond to the different digits of the second multiplier.

However, instead of using by-analysis control mechanisms (control-flow and data-flow rules)
it uses counting semaphores as a less coarse by-job control mechanism,
which allows several different multiplications to run independently of each other.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::LongMult::SemaStart;

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

        # first we flow the branch-1 into the (semaphored) funnel job:
    my ($funnel_job_id) = @{ $self->dataflow_output_id($self->input_id, 1, { -semaphore_count => scalar(@$output_ids) })  };

        # then we fan out into branch-2, and pass the $funnel_job_id to all of them
    my $fan_job_ids = $self->dataflow_output_id($output_ids, 2, { -semaphored_job_id => $funnel_job_id } );

    return 1;
}

1;

