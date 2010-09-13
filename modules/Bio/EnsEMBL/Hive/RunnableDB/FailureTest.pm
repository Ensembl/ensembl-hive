
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::FailureTest

=head1 SYNOPSIS

This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
and is ran by Workers during the execution of eHive pipelines.
It is not generally supposed to be instantiated and used outside of this framework.

Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

This RunnableDB module is used to test failure of jobs in the hive system.

It is intended for development/training purposes only.

Available parameters:

    param('value'):         is essentially your job's number.
                            If you are intending to create 100 jobs, let the param('value') take consecutive values from 1 to 100.

    param('divisor'):       defines the failure rate for this particular analysis. If the modulo (value % divisor) is 0, the job will fail.
                            For example, if param('divisor')==5, jobs with 5, 10, 15, 20, 25,... param('value') will fail.

    param('state'):         defines the state in which the jobs of this analysis may be failing.

    param('lethal_after'):  makes jobs' failures lethal when 'value' is greater than this parameter

    param('time_GET_INPUT'):    time in seconds that the job will spend sleeping in GET_INPUT state.

    param('time_RUN'):          time in seconds that the job will spend sleeping in RUN state.

    param('time_WRITE_OUTPUT'): time in seconds that the job will spend sleeping in WRITE_OUTPUT state.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::FailureTest;

use strict;

use base ('Bio::EnsEMBL::Hive::Process');

BEGIN {
#    die "Could not compile this nonsense!";
}

=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

    return {
        'value'         => 1,       # normally you generate a batch of jobs with different values of param('value')
        'divisor'       => 2,       # but the same param('divisor') and see how every param('divisor')'s job will crash
        'state'         => 'RUN',   # the state in which the process may commit apoptosis
        'lethal_after'  => 0,       # If value is above this (nonzero) threshold, job's death becomes lethal to the worker.

        'time_GET_INPUT'    => 0,   # how much time fetch_input()  will spend in sleeping state
        'time_RUN'          => 1,   # how much time run()          will spend in sleeping state
        'time_WRITE_OUTPUT' => 0,   # how much time write_output() will spend in sleeping state
    };
}

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it only calls dangerous_math() subroutine.

=cut

sub fetch_input {
    my $self = shift @_;

    $self->dangerous_math('GET_INPUT');
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it only calls dangerous_math() subroutine.

=cut

sub run {
    my $self = shift @_;

    $self->dangerous_math('RUN');
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here it only calls dangerous_math() subroutine.

=cut

sub write_output {
    my $self = shift @_;

    $self->dangerous_math('WRITE_OUTPUT');
}

=head2 dangerous_math

    Description: an internal subroutine that will first sleep for some predefined time,
                 and then either return or crash if $value is an integral multiple of $divisor.

=cut

sub dangerous_math {
    my ($self, $current_state) = @_;

        # First, sleep as required:
    sleep($self->param('time_'.$current_state));

    my $state   = $self->param('state');
    return if($current_state ne $state);

    my $value   = $self->param('value')   or die "param('value') has to be a nonzero integer";
    my $divisor = $self->param('divisor') or die "param('divisor') has to be a nonzero integer";

    if($value % $divisor == 0) {

        if(my $lethal_after = $self->param('lethal_after')) {
            if($value>$lethal_after) { # take the Worker with us into the grave
                $self->input_job->lethal_for_worker(1);
            }
        }

        die "Preprogrammed death since $value is a multiple of $divisor";
    }
}

1;

