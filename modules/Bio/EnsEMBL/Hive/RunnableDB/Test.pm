
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::Test

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

    param('time_fetching'): is time in seconds that the job will spend sleeping in FETCH_INPUT state.

    param('time_running'):  is time in seconds that the job will spend sleeping in RUN state.

    param('time_writing'):  is time in seconds that the job will spend sleeping in WRITE_OUTPUT state.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::Test;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it only sets default values of parameters and sleeps for param('time_fetching').

=cut

sub fetch_input {
    my $self = shift @_;

    $self->param_init(
        'value'         => 1,   # normally you generate a batch of jobs with different values of param('value')
        'divisor'       => 2,   # but the same param('divisor') and see how every param('divisor')'s job will crash

        'time_fetching' => 0,   # how much time fetch_input()  will spend in sleeping state
        'time_running'  => 0,   # how much time run()          will spend in sleeping state
        'time_writing'  => 0,   # how much time write_output() will spend in sleeping state
    );

        # Sleep as required:
    sleep($self->param('time_fetching'));
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it sleeps for param('time_running') and then decides whether to fail or succeed depending on param('value') and param('divisor').

=cut

sub run {
    my $self = shift @_;

    my $value   = $self->param('value');
    my $divisor = $self->param('divisor');

        # Sleep as required:
    sleep($self->param('time_running'));

    if(!$divisor or !$value) {
        die "Wrong parameters: divisor = $divisor and value = $value\n";
    } elsif ($value % $divisor == 0) {
        die "$value % $divisor is 0 => die!\n";
    }
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here it only sleeps for param('time_writing').

=cut

sub write_output {
    my $self = shift @_;

        # Sleep as required:
    sleep($self->param('time_writing'));
}

1;

