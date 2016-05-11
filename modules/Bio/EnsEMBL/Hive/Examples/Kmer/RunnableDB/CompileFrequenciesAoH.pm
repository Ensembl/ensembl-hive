=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::CompileFrequenciesAoH

=head1 SYNOPSIS

    Please refer to Bio::EnsEMBL::Hive::Examples::Kmer::PipeConfig::KmerPipelineAoH_conf pipeline configuration file
    to understand how this particular example pipeline is configured and run.

=head1 DESCRIPTION

     Kmer::RunnableDB::CompileFrequencies is the last runnable in the kmer frequency pipleine (using an array of hashes Accumulator).
     This runnable fetches kmer frequencies that the previous jobs stored in the hash Accumulator, and combines them to determine
     the overall kmer frequencies from the sequences in the original input file.

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


package Bio::EnsEMBL::Hive::Examples::Kmer::RunnableDB::CompileFrequenciesAoH;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');


=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
    In this runnable, fetch_input is left empty. It fetches data from a hive Accumulator, so there are no extra database
    connections to open, nor files to check. It's more sensible to fetch data from the Accumulator in run, where it's needed
    rather than to fetch it here, then pass it along in another parameter. 

=cut

sub fetch_input {

}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).

    In this method, we fetch kmer counts produced by previous jobs and stored in an Accumulator. We sum up the
    number of times each kmer is found over all the chunks, and store the sums in a param. Storing the results
    in a param makes them available to other methods in this runnable -- specifically write_output.

    In this pipeline, each kmer, and its frequency, have been stored in an Accumulator as key-value pairs - 
    much like a Perl hash. The value is simply the number of times that kmer appeared in a given chunk.

    The key is a bit more complicated because in Accumulators, as with Perl hashes, keys need to be unique.
    However, the same kmer may appear in many chunks - so if the kmer sequence alone were the key, the count of
    a kmer for one chunk would overwrite the count for the same kmer in a different chunk. To disambiguate things,
    we make the key look like "chunk:kmer" - for example, the kmer "ACGT" found in the file "chunk1.fa" 
    would be given the key "chunk1.fa:ACGT"

=cut

sub run {
    my $self = shift @_;

    # Accessing the Accumulator by it's name ('freq'), as a param.
    # We get a hashref back.
    my $freq = $self->param('freq'); 

    my %sum_of_frequencies;

    # $freq is a hashref - the keys are chunk:kmer,
    # the values are the counts for kmer in that chunk.

    foreach my $kmer_group (@{$freq}) {
      foreach my $kmer (keys(%{$kmer_group})) {
	  $sum_of_frequencies{$kmer} += $kmer_group->{$kmer};
      }
    }
    $self->param('sum_of_frequencies', \%sum_of_frequencies);
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.

    Here, we flow out two values:
    * kmer      -- the kmer being counted
    * frequency -- frequency of that kmer across all files

=cut

sub write_output {
  my $self = shift(@_);

  my $sum_of_frequencies = $self->param('sum_of_frequencies');

  foreach my $kmer (keys(%{$sum_of_frequencies})) {
    $self->dataflow_output_id({
			       'kmer' => $kmer,
			       'frequency' => $sum_of_frequencies->{$kmer}
			      }, 1);
  }
}

1;
