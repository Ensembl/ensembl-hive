=pod 

=head1 NAME

    GCPct::RunnableDB::CountATGC

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf pipeline configuration file
    to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

    'GCPct::RunnableDB::CountATGC' determines AT and GC frequencies in sequence(s) in a .fasta file, then stores
    those frequencies in an accumulator

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


package GCPct::RunnableDB::CountATGC;

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
                  Here we have nothing to fetch.

=cut

sub fetch_input {
  my $self = shift @_;

    my $chunkfile = $self->param_required('chunk_name');

    my $chunkin = Bio::SeqIO->new(-file => "$chunkfile");

    $self->param('chunkin', $chunkin);

}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  The only thing we do here is make a call to the recursive function that will compute the product.

    param('a_multiplier'):  The first long number (a string of digits - doesn't have to fit a register).

    param('digit'):         A decimal digit that is a part of the second multiplier.

    param('take_time'):     How much time to spend sleeping (seconds).

=cut

sub run {   # call the recursive function that will compute the stuff
    my $self = shift @_;

    my $at_count = 0;
    my $gc_count = 0;
    foreach my $chunkseq ($self->param('chunkin')->next_seq()) {
      my $seqstring = $chunkseq->seq();
      $at_count += @{[$seqstring =~ /([AaTt])/g]};
      $gc_count += @{[$seqstring =~ /([GgCc])/g]};
    }

    $self->param('at_count', $at_count);
    $self->param('gc_count', $gc_count);

    sleep( $self->param('take_time') );
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Dataflows the intermediate results down branch 1, which will be routed into 'partial_product' accumulator.

=cut

sub write_output {  # but this time we have something to store
    my $self = shift @_;

    $self->dataflow_output_id( {
				'at_count'   => $self->param('at_count'),
				'gc_count' => $self->param('gc_count'),
    }, 1);
}

=head2 _rec_multiply
    
    Description: this is a private function (not a method) that performs recursive multiplication of a long number by a digit with a carry.

=cut

sub _rec_multiply {
    my ($a_multiplier, $digit, $carry) = @_;

        # recursion end:
    unless($a_multiplier) {
        return ($carry || '');
    }

        # recursion step:
    if($a_multiplier=~/^(\d*)(\d)$/) {
        my ($prefix, $last_digit) = ($1, $2);

        my $this_product = $last_digit*$digit+$carry;
        my $this_result  = $this_product % 10;
        my $this_carry   = int($this_product / 10);

        return _rec_multiply($prefix, $digit, $this_carry).$this_result;
    } else {
        die "'a_multiplier' has to be a decimal number";
    }
}

1;

