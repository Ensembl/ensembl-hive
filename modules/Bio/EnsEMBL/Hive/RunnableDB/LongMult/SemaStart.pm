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

    my $analysis_adaptor = $self->db->get_AnalysisAdaptor();
    my $job_adaptor      = $self->db->get_AnalysisJobAdaptor();

    my $pm_analysis    = $analysis_adaptor->fetch_by_logic_name('part_multiply');
    my $at_analysis    = $analysis_adaptor->fetch_by_logic_name('add_together');
    my $current_job_id = $self->input_job->dbID();

        # First, create the "sink" job and pre-block it with counting semaphore
    my $at_job_id = $job_adaptor->CreateNewJob (
            -input_id        => "{ 'a_multiplier' => '$a_multiplier', 'b_multiplier' => '$b_multiplier' }",
            -analysis        => $at_analysis,
            -input_job_id    => $current_job_id,
            -semaphore_count => scalar (keys %digit_hash),  # AT MOST that many individual blocks
    );

        # Then, create the array of intermediate jobs that will be gradually unblocking the "sink" job upon successful completion:
    foreach my $digit (keys %digit_hash) {
        my $pm_job_id = $job_adaptor->CreateNewJob (
            -input_id          => "{ 'a_multiplier' => '$a_multiplier', 'digit' => '$digit' }",
            -analysis          => $pm_analysis,
            -input_job_id      => $current_job_id,
            -semaphored_job_id => $at_job_id,
        );

            # if this job has already been created in the past
            # (and presumably the result has been already computed),
            # we want to adjust the semaphore_count manually :
        unless($pm_job_id) {
            $job_adaptor->decrease_semaphore_count_for_jobid($at_job_id);
        }
    }
}

sub write_output {  # and we have nothing to write out
    my $self = shift @_;

    return 1;
}

1;

