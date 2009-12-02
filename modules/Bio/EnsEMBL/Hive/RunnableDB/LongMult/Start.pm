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

    my $pm_analysis    = $self->db->get_AnalysisAdaptor()->fetch_by_logic_name('part_multiply');
    my $current_job_id = $self->input_job->dbID();

    foreach my $digit (keys %digit_hash) {
        Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob (
            -input_id       => "{ 'a_multiplier' => '$a_multiplier', 'digit' => '$digit' }",
            -analysis       => $pm_analysis,
            -input_job_id   => $current_job_id,
        );
    }
}

sub write_output {  # and we have nothing to write out
    my $self = shift @_;

    $self->dataflow_output_id($self->input_id); # flow into an 'add_together' job

    return 1;
}

1;

