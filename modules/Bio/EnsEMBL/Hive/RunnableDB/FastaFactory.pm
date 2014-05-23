=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::FastaFactory

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FastaFactory --inputfile reference.fasta --max_chunk_length 600000

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::FastaFactory \
                    --inputfile reference.fasta \
                    --max_chunk_length 700000 \
                    --output_prefix ref_chunk \
                    --flow_into "{ 2 => ['mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1/lg4_split_fasta/analysis?logic_name=blast']}"

=head1 DESCRIPTION

    This is a Bioinformatics-specific "Factory" Runnable that splits a given Fasta file into smaller chunks
    and dataflows one job per chunk.

    The following parameters are supported:

        param('inputfile');         # The original Fasta file: 'inputfile' => 'my_sequences.fasta'

        param('max_chunk_length');  # Maximum total length of sequences in a chunk: 'max_chunk_length' => '200000'

        param('output_prefix');     # A common prefix for output files: 'output_prefix' => 'my_special_chunk_'

        param('output_suffix');     # A common suffix for output files: 'output_suffix' => '.nt'

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::FastaFactory;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');
use Bio::SeqIO;


=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

    return {
        'max_chunk_length'  => 100000,
        'output_prefix'     => 'my_chunk_',
        'output_suffix'     => '.fasta',
    };
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                    Here we only check the existence of 'inputfile' parameter and try to parse it (all other parameters have defaults).

=cut

sub fetch_input {
    my $self = shift @_;

    my $inputfile   = $self->param_required('inputfile');
    die "Cannot read '$inputfile'" unless(-r $inputfile);

    if($inputfile=~/\.(?:gz|Z)$/) {
        $inputfile = "gunzip -c $inputfile |";
    }
    my $input_seqio = Bio::SeqIO->new(-file => $inputfile)  || die "Could not open or parse '$inputfile', please investigate";

    $self->param('input_seqio', $input_seqio);
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                    Because we want to stream the data more efficiently, all functionality is in write_output();

=cut

sub run {
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                    The main bulk of this Runnable's functionality is here.
                    Iterates through all sequences in input_seqio, splits them into separate files ("chunks") using a cut-off length and dataflows one job per chunk.

=cut

sub write_output {
    my $self = shift @_;

    my $input_seqio         = $self->param('input_seqio');
    my $max_chunk_length    = $self->param('max_chunk_length');
    my $output_prefix       = $self->param('output_prefix');
    my $output_suffix       = $self->param('output_suffix');

    my $chunk_number = 1;   # counts the chunks
    my $chunk_length = 0;   # total length of the current chunk
    my $chunk_size   = 0;   # number of sequences in the current chunk
    my $chunk_name   = $output_prefix.$chunk_number.$output_suffix;
    my $chunk_seqio  = Bio::SeqIO->new(-file => '>'.$chunk_name, -format => 'fasta');

    while (my $seq_object = $input_seqio->next_seq) {
        if((my $seq_length = $seq_object->length()) + $chunk_length <= $max_chunk_length) {

                # add to the current chunk:
            $chunk_seqio->write_seq( $seq_object );
            $chunk_length += $seq_length;
            $chunk_size   += 1;
        } else {

                # dataflow the current chunk:
            $self->dataflow_output_id( {
                'chunk_name' => $chunk_name,
                'chunk_number' => $chunk_number,
                'chunk_length' => $chunk_length,
                'chunk_size' => $chunk_size
            }, 2);

                # start writing to the next one:
            $chunk_length   = 0;
            $chunk_size     = 0;
            $chunk_number++;
            $chunk_name     = $output_prefix.$chunk_number.$output_suffix;
            $chunk_seqio    = Bio::SeqIO->new(-file => '>'.$chunk_name, -format => 'fasta');
        }
    }

    if($chunk_size) {   # flush the last chunk:

        $self->dataflow_output_id( {
            'chunk_name' => $chunk_name,
            'chunk_number' => $chunk_number,
            'chunk_length' => $chunk_length,
            'chunk_size' => $chunk_size
        }, 2);
    }
}

1;

