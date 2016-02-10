=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf;

=head1 SYNOPSIS

       # initialize the database and build the graph in it (it will also print the value of EHIVE_URL) :
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass>

        # optionally also seed it with your specific values:
    seed_pipeline.pl -url $EHIVE_URL -logic_name take_b_apart -input_id '{ "sequence" => "gcpct_example.fa" }'

        # run the pipeline:
    beekeeper.pl -url $EHIVE_URL -loop

=head1 DESCRIPTION

    This is the PipeConfig file for the %GC pipeline example.
    The main point of this pipeline is to provide an example of how to write Hive Runnables and link them together into a pipeline.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf module to understand the interface implemented here.

    The setting. Let's assume we are given a nucleotide sequence and want to calculate what percentage of bases are G or C.
    The approach to this problem is quite simple: go through the sequence, tally up how many times a G or C occurs, then divide by the total number of bases in the sequence.
    Thinking a bit more about this problem, we see that it is very easy to split up into smaller subproblems. 
    Each base is its own, independant entity, and they can be tallied in any order, or even simultaneously, without impacting the final result.
    (As an aside, this problem falls into a class of problems that computer scientists call "embarrasingly parallell" or "pleasingly parallell",
     as they are so easy to divide.)
    We can take advantage of this and speed up the computation on longer sequences by splitting up the input sequence into smaller chunks, 
    tallying Gs and Cs in those chunks in parallel, then adding up the individual results into a final total.

    The %gc pipeline consists of three "analyses" (types of tasks):
        chunk_sequences, 'count_atgc', and 'calc_overall_percentage' that we use to examplify various features of the Hive.

        * A chunk_sequences job takes sequences in a .fasta format file and splits them
          into smaller chunks. It creates a set of new .fasta format files to store these sequence chunks. It creates
          one new job for each of the new .fasta files it creates. In this configuration file, we specify that each of these
          new jobs will be a 'count_atgc' job. 

        * A 'count_atgc' job takes in a string parameter 'fasta_filename', then tllies up the number of As, Cs, Gs and Ts in the sequence(s)
          in that file, accumulating them in the 'at_count' and 'gc_count' accumulators.

        * A 'calc_overall_percentage' job waits for all count_atgc jobs to complete. It takes in the 'at_count' and 'gc_count' hashes
          and produces the final result in the final_resutl table.

    Please see the implementation details in Runnable modules themselves.

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


package Bio::EnsEMBL::Hive::PipeConfig::GCPct_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates two pipeline-specific tables used by Runnables to communicate.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

            # additional tables needed for long multiplication pipeline's operation:
        $self->db_cmd('CREATE TABLE final_result (inputfile varchar(255) NOT NULL, result varchar(255) NOT NULL, PRIMARY KEY (inputfile))'),
    ];
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure now (will be stringified and de-stringified automagically).
                  Please see existing PipeConfig modules for examples.

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'take_time'     => 1,
    };
}


sub hive_meta_table {
    my ($self) = @_;
    return {
        %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:
                    * 'chunk_sequences' which uses the FastaFactory runnable to split sequences in an input .fasta file
                       into smaller chunks

                    * 'count_atgc' which takes a chunk produced by chunk_sequences, and tallies the number of occurances of each base
                      in the sequence(s) in the file

                    * 'calc_overall_percentage' which takes the base count subtotals from all count_atgc jobs and calculates the
                      overall %GC in the sequence(s) in the original input .fasta Until the hash is complete the
                      'calc_overall_percentage' job is blocked by a semaphore.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'chunk_sequences',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
            -input_ids => [
                { 'inputfile' => 'input_fasta.fa', 
		  'max_chunk_length' => '1000000',
		  'output_prefix' => 'gcpct_input_chunk_',
		},
            ],
            -flow_into => {
                '2->A' => [ 'count_atgc' ],   # will create a semaphored fan of jobs; will use param_stack mechanism to pass parameters around
                'A->1' => [ 'calc_overall_percentage'  ],   # will create a semaphored funnel job to wait for the fan to complete and add the results
            },
        },

        {   -logic_name => 'count_atgc',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::GCPct::CountATGC',
            -analysis_capacity  =>  4,  # use per-analysis limiter
            -flow_into => {
                1 => [ ':////accu?at_count=[]',
		       ':////accu?gc_count=[]'],
            },
        },
        
        {   -logic_name => 'calc_overall_percentage',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::GCPct::CalcOverallPercentage',
#           -analysis_capacity  =>  0,  # this is a way to temporarily block a given analysis
            -flow_into => {
                1 => [ ':////final_result', 'last' ],
            },
        },

        {   -logic_name => 'last',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        }
    ];
}

1;

