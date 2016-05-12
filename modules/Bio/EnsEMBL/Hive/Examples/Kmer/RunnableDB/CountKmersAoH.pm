=pod 

=head1 NAME

   Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::CountKmersAoH

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::Examples::Kmer::PipeConfig::Kmer_conf pipeline configuration file
    to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

    'Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::CountKmersAoH is a runnable that counts the number of k-mers in a DNA sequence.

    As input, it takes the name of a file with a DNA sequence,
    the format of that file (which must be supported by Bio::SeqIO), 
    k (in bases),
    and a "discard last k-mer" flag.

    The "discard last k-mer" flag exists to prevent double-counting k-mers if the sequence is part
    of a series of overlapping subsequences. If "discard last k-mer" is non-zero, then the final k-mer 
    in the sequence will be discarded

    k must be >= 1.

    It flows out each k-mer seen, and the frequency of the k-mer in the (sub)sequence as key-value pairs.
    The key is the k-mer, and the value being the frequency.


=head1 LICENSE

    Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

package Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::CountKmersAoH;

use strict;
use warnings;

use Bio::SeqIO;

use Data::Dumper;

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

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).

    Here, run() reads in the filename of a file containing a DNA sequence, 
    the format of that file (e.g. 'FASTA' - the format must be supported by Bio::SeqIO),
    k,
    and the 'discard last k-mer' option.

    param('sequence_file'):      Name of the file containing the sequence
    param('input_format'):       Format of the sequence file (e.g. FASTA)
    param('k'):                  k
    param('discard_last_kmer'):  Discard the last k-mer found in the sequence (useful if this sequence is part of a series of overlapping sub-sequences, to prevent double-counting overlapping k-mers).

=cut

sub run {
  my $self = shift;

  my $sequence_file = $self->param_required('sequence_file');
  my $input_format = $self->param('input_format');
  my $k = $self->param_required('k');

  my $input_seqio;
  if ( $sequence_file =~ /\.(?:gz|Z)$/) {
    open(my $in_fh, '-|', "gunzip -c $sequence_file");
    $input_seqio = Bio::SeqIO->new(-fh => $in_fh, -format => $self->param_required('input_format'));
    $self->param('input_fh', $in_fh); # storing as a param so that it can be closed by post_cleanup if necessary 
  } else {
    $input_seqio = Bio::SeqIO->new(-file => $sequence_file);
  }
  die "Could not open or parse '$sequence_file', please investigate" unless $input_seqio;

  my $kmer_counts = _count_kmers($input_seqio, $k);
  $self->param('kmer_counts', $kmer_counts);
}

=head2 write_output

    Description: Implements the write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to flow output to the rest of the pipeline.
                 Here, we flow out two values:
                 * kmer -- the k-mer sequence
                 * freq -- the frequency of that k-mer

=cut

sub write_output {
  my $self = shift @_;

  my $kmer_counts = $self->param('kmer_counts');

  foreach my $kmer(keys(%{$kmer_counts})) {
    $self->dataflow_output_id( {'kmer' => $kmer,
				'freq' => $kmer_counts->{$kmer}
			       }, 3);
  }

}

=head2 _count_kmers

    Description: Private method to identify and count k-mers in a sequence.

    Arg [1] : A Bio::SeqIO input filehandle.
    Arg [2] : k
    Arg [3] : If not 0, then discard (do not count) the last k-mer in the string

    Return  : A hashref of k-mer frequencies. key = k-mer, value = frequency
=cut

sub _count_kmers {
  my ($seqio, $k) = @_;
  my %kmer_counts;

  while (my $seqobj = $seqio->next_seq()) { 
    my $seq = $seqobj->seq();

    my $last_kmer_start = (length($seq) - $k) + 1;
    for (my $i = 0; $i < $last_kmer_start; $i++) {
      my $kmer = substr($seq, $i, $k);
      $kmer_counts{$kmer}++;
    }
  }
  return \%kmer_counts;
}

1;
