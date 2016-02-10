=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::GCPct::CalcOverallPercentage

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf pipeline configuration file
    to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

    'GCPct::CalcOverallPercentage' is the final step of the pipeline. It sums up the GC and AT counts from all of the chunked subsequences,
    then divides the GC count by the total nucleotide count to determine %GC

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


package Bio::EnsEMBL::Hive::RunnableDB::GCPct::CalcOverallPercentage;

use strict;
use warnings;

use List::Util qw(reduce);

use base ('Bio::EnsEMBL::Hive::Process');


=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

    return {
        'take_time'                 => 0,       # how much time run() method will spend in sleeping state
    };
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here all relevant partial products are fetched from the 'partial_product' accumulator and stored in a hash for future use.

    param('a_multiplier'):  The first long number (a string of digits - doesn't have to fit a register).

    param('b_multiplier'):  The second long number (also a string of digits).

    param('take_time'):     How much time to spend sleeping (seconds).

=cut

sub fetch_input {   # fetch all the (relevant) precomputed products
    my $self = shift @_;

    # my $at_count = $self->param('at_count');
    # my $gc_count = $self->param('gc_count');
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  The only thing we do here is make a call to the function that will add together the intermediate results.

=cut

sub run {   # call the function that will compute the stuff
    my $self = shift @_;

    my $at_count = $self->param('at_count');
    my $gc_count = $self->param('gc_count');

    my $percentage = $self->_calc_pct($at_count, $gc_count);

    $self->param('result', $percentage);
    $self->warning("percentage is $percentage");
    
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Dataflows both original multipliers and the final result down branch-1, which will be routed into 'final_result' table.

=cut


sub write_output {  # store and dataflow
    my $self = shift @_;

    $self->dataflow_output_id({
        'result'       => $self->param('result'),
    }, 1);
}

sub _calc_pct {
  my ($self, $at_count, $gc_count) = @_;

  # as Perl doesn't have reduce, just map...
  my $at_sum = reduce {$a + $b} @{$at_count};
  my $gc_sum = reduce {$a + $b} @{$gc_count};

  my $pct_gc = 0;
  if (($at_sum + $gc_sum) != 0) {
    $pct_gc = $gc_sum / ($at_sum + $gc_sum);
  }
  return $pct_gc;
}

1;

