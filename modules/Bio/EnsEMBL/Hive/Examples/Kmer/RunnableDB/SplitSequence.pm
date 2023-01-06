=pod 

=head1 NAME

   Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::SplitSequence

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::Examples::Kmer::PipeConfig::Kmer_conf pipeline configuration file
    to understand how this particular example pipeline is configured and ran.

=head1 DESCRIPTION

    'Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::SplitSequence is a utility runnable to split a DNA sequence into several shorter, 
    overlapping subsequences. (Compare Bio::EnsEMBL::Hive::RunnableDB::FastaFactory, which splits a file containing many sequences
    into several files containing some of the sequences in the original file, but keeps the sequences intact).

    As input, it takes the name of a file with one or more DNA sequences,
    the format of that file (which must be supported by Bio::SeqIO), 
    a chunk size in base-pairs (BP),
    and an overlap size, also in BP.

    Overlap size must be >= 1. Chunk size must be > overlap size.

    From this, it generates subsequences [chunk-size] BP long, overlapping each other by [overlap-size] BP.
    The last chunk may be shorter than [chunk-size] BP, but will always be at least [overlap-size] + 1 BP

    It then stores each of these chunks into new FASTA-format files, one chunk per file.

    It flows out each chunk's filename, along with a flag indicating if a particular chunk is the last chunk
    from the original sequence.


=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

package Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::SplitSequence;

use strict;
use warnings;

use Bio::SeqIO;
use Bio::Seq;

use Data::Dumper;

use base ('Bio::EnsEMBL::Hive::Process');

=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

  return {
	  'output_dir'        => '.',
	  'output_prefix'     => 'my_chunk_',
	  'output_suffix'     => '.fasta',
	  'input_format'      => 'FASTA',
	 };
}

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.

    There are no hard and fast rules on whether to fetch parameters in fetch_input(), or to wait until run() to fetch them.
    In general, fetch_input() is a place to validate parameter existence and values for errors before the worker get set into RUN state
    from the FETCH_INPUT state. 

    

=cut

sub fetch_input {

}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).

    Here, run() reads in the filename of a file containing a DNA sequence, an integer chunk-size in bases,
    and an integer overlap size in bases. The file needs to be in a format supported by Bio::SeqIO.

    param('inputfile'):     Name of the file containing the sequence to split
    param('input_format'):  Format of the sequence file (e.g. FASTA)
    param('chunk_size'):    Desired chunk size in base-pairs
    param('overlap_size'):  Desired length of overlap between chunks, in base-pairs



=cut

sub run {
  my $self = shift @_;
  
  my $inputfile = $self->param_required('inputfile');
  my $chunk_size = $self->param_required('chunk_size');
  my $overlap_size = $self->param_required('overlap_size');

  my $input_seqio;
  if ( $inputfile =~ /\.(?:gz|Z)$/) {
    open(my $in_fh, '-|', "gunzip -c $inputfile");
    $input_seqio = Bio::SeqIO->new(-fh => $in_fh, -format => $self->param('input_format'));
    $self->param('input_fh', $in_fh); # storing as a param so that it can be closed by post_cleanup if necessary 
  } else {
    $input_seqio = Bio::SeqIO->new(-file => $inputfile, -format => $self->param('input_format'));
    $self->param('input_fh', undef);
  }
  die "Could not open or parse '$inputfile', please investigate" unless $input_seqio;


  if (($chunk_size < 1) ||
      ($overlap_size < 0) ||
      ($overlap_size >= $chunk_size)) {
    die "chunk_size must be > overlap_size, and both must be positive";
  }

  my $split_sequences = _split_sequences($input_seqio, $chunk_size, $overlap_size);
  $self->param('split_sequences', $split_sequences);
}

=head2 write_output

    Description: Implements the write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to flow output to the rest of the pipeline.

    Here, we flow out two values:
    * chunk_name    -- the name of a file containing a sequence chunk
    * output_format -- the format of the output file. For this runnable, this is hard-coded as 'FASTA'
                       as it always outputs FASTA format files

=cut


sub write_output {
  my $self = shift @_;

  my @split_sequences = @{$self->param('split_sequences')};

  for (my $i = 0; $i <= $#split_sequences; $i++) {
    my $seq_object = Bio::Seq->new(-seq => $split_sequences[$i],
				   -id => "split_" . $i);

    my $chunk_filename = ($self->param('output_dir') ? $self->param('output_dir') . '/' : '' ) . $self->param('output_prefix') . $i . $self->param('output_suffix');
    my $chunk_seqio = Bio::SeqIO->new(-file => '>' . $chunk_filename,
				      -format => 'fasta');

    $chunk_seqio->write_seq($seq_object);


    $self->dataflow_output_id( {'chunk_name' => $chunk_filename,
				'output_format' => 'FASTA',
			       }, 2);
  }

}

=head2 post_cleanup

    Description: Here, we implement the post_cleanup method of Bio::EnsEMBL::Hive::Process that is used to take care
of housekeeping details after a runnable finishes.

    This method will run even if the job fails, or write_output never gets called - so it's somewhat analogous to
    the finalize methods many languages implement as part of exception handling.

    In this case, it ensures the input filehandle gets closed.

=cut

sub post_cleanup {
  my $self = shift;
  close( $self->param('input_fh') ) if $self->param('input_fh');
}

=head2 _split_sequence

    Description: This is a private function (not a method, so it doesn't know about parameters) 
    that takes a long sequence and returns a collection of shorter subsequences.

    Arg [1] : The sequence, as a string
    Arg [2] : The length of each subsequence (if possible). Subsequences will be no longer than
              this value, but one may be shorter
    Arg [3] : Number of bases to overlap adjacent subsequences

=cut

sub _split_sequences {
  my ($seqio, $chunk_size, $overlap_size) = @_;

  my @split_sequences;

  while (my $seq = $seqio->next_seq()) {
    my $seq_str = $seq->seq();

    $seq_str = uc($seq_str);
    my $chunk_pointer = 0;
    my $last_chunk = 0;
    my $chunk_substring_size = $chunk_size;
    do {
      my $chunk_end = ($chunk_pointer + $chunk_size) - 1;
      if ($chunk_end > length($seq_str)) {
	$chunk_end = length($seq_str) - 1;
	$chunk_substring_size = ($chunk_end - $chunk_pointer) + 1;
	$last_chunk = 1;
      }
      my $subseq = substr($seq_str, $chunk_pointer, $chunk_substring_size);
      push(@split_sequences, $subseq);
      
      $chunk_pointer = (($chunk_end + 1) - $overlap_size);
    } while ($last_chunk == 0);
  }

  return \@split_sequences;
}

1;
