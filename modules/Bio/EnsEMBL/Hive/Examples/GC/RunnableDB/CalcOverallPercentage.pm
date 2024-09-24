=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CalcOverallPercentage

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf pipeline configuration file
    to see how this runnable fits into the %GC example pipeline.

=head1 DESCRIPTION

    'Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CalcOverallPercentage' is the final step of the pipeline. 
    It sums up the GC and AT counts from all of the chunked subsequences, then divides the GC count by the GC + AT 
    count to determine %GC

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CalcOverallPercentage;

use strict;
use warnings;

use List::Util qw(sum);

use base ('Bio::EnsEMBL::Hive::Process');


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.

    There are no hard and fast rules on whether to fetch parameters in fetch_input(), or to wait until run() to fetch them.
    In general, fetch_input() is a place to validate parameter existence and values for errors before the worker get set into RUN state
    from the FETCH_INPUT state. In this case, since it's a simple computation, we don't do anything in fetch_input() and instead just
    handle the parameters in run()

=cut

sub fetch_input {   

}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job.
                  Here, we fetch AT and GC counts, then call a subroutine to calculate %GC from the counts.

=cut

sub run { 
    my $self = shift @_;

    my $at_count = $self->param_required('at_count');
    my $gc_count = $self->param_required('gc_count');

    my $percentage = $self->_calc_pct($at_count, $gc_count);

    $self->param('result', $percentage);
    $self->warning("percentage is $percentage");
    
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output 
                  after the execution.
                  Here, it flows the result from the %GC calculation out into branch 1 in a parameter called 'result'.

=cut


sub write_output {  # dataflow
    my $self = shift @_;

    $self->dataflow_output_id({
        'result'       => $self->param('result'),
    }, 1);
}

=head2 _calc_pct

    Description : This is a private method that does the actual %GC calculation.
                  $at_count is an arrayref pointing to a list of AT counts;
                  likewise, $gc_count is an arrayref pointint to a list of GC counts. In the
                  %GC pipeline, each element in the array is the count of AT or GC in one of the chunked
                  sequence files.

                  Here, we sum up the counts from all of the chunks, then divide the total GC count by the
                  total AT + GC count to determine a percentage.
                  
=cut

sub _calc_pct {
  my ($self, $at_count, $gc_count) = @_;

  # using sum from List::Util
  my $at_sum = sum @{$at_count};
  my $gc_sum = sum @{$gc_count};

  my $pct_gc = 0;
  if (($at_sum + $gc_sum) != 0) {
    $pct_gc = $gc_sum / ($at_sum + $gc_sum);
  }
  return $pct_gc;
}

1;

