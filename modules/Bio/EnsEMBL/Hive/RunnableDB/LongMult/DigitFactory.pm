=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::LongMult::DigitFactory

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf pipeline configuration file
    to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

    'LongMult::DigitFactory' is the first step of the LongMult example pipeline that multiplies two long numbers.

    It takes apart the second multiplier and creates several 'LongMult::PartMultiply' jobs
    that correspond to the different digits of the second multiplier.

    It also "flows into" one 'LongMult::AddTogether' job that will wait until 'LongMult::PartMultiply' jobs
    complete and will arrive at the final result.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::LongMult::DigitFactory;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');


=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

    return {
        'take_time' => 0,   # how much time run() method will spend in sleeping state
    };
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here the task of fetch_input() is to read in the two multipliers, split the second one into digits and create a set of input_ids that will be used later.

    param('b_multiplier'):  The second long number (a string of digits - doesn't have to fit a register)

    param('take_time'):     How much time to spend sleeping (seconds).

=cut

sub fetch_input {
    my $self = shift @_;

    my $b_multiplier    = $self->param_required('b_multiplier');

    my %digit_hash = ();
    foreach my $digit (split(//,$b_multiplier)) {
        next if (($digit eq '0') or ($digit eq '1'));
        $digit_hash{$digit}++;
    }

        # parameter hashes of partial multiplications to be computed:
    my @sub_tasks = map { { 'digit' => $_ } } keys %digit_hash;

        # store them for future use:
    $self->param('sub_tasks', \@sub_tasks);
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here we don't have any real work to do, just input and output, so run() just spends some time waiting.

=cut

sub run {
    my $self = shift @_;

    sleep( $self->param('take_time') );
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we dataflow all the partial multiplication jobs whose input_ids were generated in fetch_input() into the branch-2 ("fan out"),
                  and also dataflow the original task down branch-1 (create the "funnel job").

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $sub_tasks = $self->param('sub_tasks');

        # "fan out" into branch#2 first, branch#1 will be created if we wire it (and we do)
    $self->dataflow_output_id($sub_tasks, 2);

    $self->warning(scalar(@$sub_tasks).' multiplication jobs have been created');     # warning messages get recorded into 'log_message' table

## extra information sent to the funnel will extend its stack:
#    $self->dataflow_output_id( { 'different_digits' => scalar(@$sub_tasks) } , 1);
}

1;

