=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CountATGC

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf pipeline configuration file
    to see how this runnable fits into the %GC example pipeline.

=head1 DESCRIPTION

    'Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CountATGC' counts the occurrences of A/T and G/C bases in
    the sequences in a .fasta file. It takes a .fasta file with DNA sequences as input. It flows out two parameters:
    at_count and gc_count.

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


package Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CountATGC;

use strict;
use warnings;

use Bio::SeqIO;

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
                  There are no hard and fast rules on whether to fetch parameters in fetch_input(), or to wait until run() to fetch them.
                  In general, fetch_input() is a place to validate parameter existence and values for errors before the worker get set into RUN state 
                  from the FETCH_INPUT state.

                  In this case, we decide to try and open our input file in fetch_input(), so that it will fail early if there is a problem with the
                  file open operation.

=cut

sub fetch_input {
  my $self = shift @_;

    my $chunkfile = $self->param_required('chunk_name');
    my $chunk_in = Bio::SeqIO->new(-file => "$chunkfile");
    $self->param('chunk_in', $chunk_in);

}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job.
                  Here, we use the file opened in fetch_input, read in the sequences from the file, and tally up the number of 
                  AT and GC bases seen. We then store these in parameters named at_count and gc_count.

=cut

sub run { 
    my $self = shift @_;

    my $at_count = 0;
    my $gc_count = 0;
    foreach my $chunkseq ($self->param('chunk_in')->next_seq()) {
      my $seqstring = $chunkseq->seq();
      $at_count += @{[$seqstring =~ /([AaTt])/g]};
      $gc_count += @{[$seqstring =~ /([GgCc])/g]};
    }

    $self->param('at_count', $at_count);
    $self->param('gc_count', $gc_count);

    sleep( $self->param('take_time') );
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with  the 
                  job's output after the execution.
                  The AT and GC counts dataflow down branch 1 in two parameters: 'at_count' and 'gc_count'.

=cut

sub write_output {  # but this time we have something to store
    my $self = shift @_;

    $self->dataflow_output_id( {
				'at_count' => $self->param('at_count'),
				'gc_count' => $self->param('gc_count'),
    }, 1);
}

1;

