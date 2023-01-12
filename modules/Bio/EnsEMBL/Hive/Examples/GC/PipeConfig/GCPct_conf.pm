=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Examples::GC::PipeConfig::GCPct_conf

=head1 SYNOPSIS

       # initialize the database and build the graph in it (it will also print the value of EHIVE_URL) :
    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::GC::PipeConfig::GCPct_conf -password <mypass>

        # optionally also seed it with your specific values:
    seed_pipeline.pl -url $EHIVE_URL -logic_name chunk_sequences -input_id '{ "sequence" => "gcpct_example.fa" }'

        # run the pipeline:
    beekeeper.pl -url $EHIVE_URL -loop

=head1 DESCRIPTION

    This is the PipeConfig file for the %GC pipeline example.
    The main point of this pipeline is to provide an example of how to write Hive Runnables and link them together into a pipeline.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf module to understand the interface implemented here.

    The setting. Let's assume we are given a nucleotide sequence and want to calculate what percentage of bases are G or C.
    The approach to this problem is quite simple: go through the sequence, tally up how many times a G or C occurs, then divide by the total number of bases in the sequence.
    Thinking a bit more about this problem, we see that it is very easy to split up into smaller subproblems. 
    Each base is its own, independent entity, and they can be tallied in any order, or even simultaneously, without impacting the final result.
    (As an aside, this problem falls into a class of problems that computer scientists call "embarrassingly parallel" or "pleasingly parallel",
     as they are so easy to divide.)
    We can take advantage of this and speed up the computation on longer sequences by splitting up the input sequences into smaller chunks, 
    tallying Gs and Cs in those chunks in parallel, then adding up the individual results into a final total.

    The %GC pipeline consists of three "analyses" (types of tasks):
        'chunk_sequences', 'count_atgc', and 'calc_overall_percentage' that we use to exemplify various features of the Hive.

        * A chunk_sequences job takes sequences in a file and splits them
          into smaller chunks. It creates a set of new files to store these sequence chunks. It creates
          one new job for each of the new files it creates. In this configuration file, we specify that each of these
          new jobs will be a 'count_atgc' job. 

        * A 'count_atgc' job takes in a string parameter 'fasta_filename', then tallies up the number of As, Cs, Gs and Ts in the sequence(s)
          in that file. It outputs the tallies as two parameters: 'at_count' and 'gc_count'. In this pipeline, 
          these parameters are flowed into two accumulators, also called 'at_count' and 'gc_count' where they are
          stored for later use.

        * The 'calc_overall_percentage' job is run after all count_atgc jobs have completed. 
          It takes in the tallied AT and GC counts from the 'at_count' and 'gc_count' accumulators,
          calculates the overall GC percentage, and outputs it as a 'result' parameter.
          This pipeline then flows that result into the 'final_results' table.

    Please see the implementation details in Runnable modules themselves.

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


package Bio::EnsEMBL::Hive::Examples::GC::PipeConfig::GCPct_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf 
                  that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it 
                  also creates a pipeline-specific table called 'final_result' to store the results of the computation.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

        # create an additional table to store the end result of the computation:
        $self->db_cmd('CREATE TABLE final_result (inputfile VARCHAR(255) NOT NULL, result DOUBLE PRECISION NOT NULL, PRIMARY KEY (inputfile))'),
    ];
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of 
                  pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, it can be any Perl structure. (They will be stringified and
                  de-stringified automagically).

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

            # init_pipeline.pl makes the best guess of the hive root directory and stores it in EHIVE_ROOT_DIR, if it wasn't already set in the shell
        'inputfile'     => $ENV{'EHIVE_ROOT_DIR'} . '/t/input_fasta.fa',    # name of the input file, here set to a sample file included with the eHive distribution
        'input_format'  => 'FASTA',                                         # the expected format of the input file

            # Because this is an example pipeline, we provide a way to slow down execution so
            # that it can be more easily observed as it runs. The 'take_time' parameter,
            # specifies how much additional time a step should take before setting itself
            # to "DONE."
        'take_time'     => 1,
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that 
                  defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:
                    * 'chunk_sequences' which uses the FastaFactory runnable to split sequences in an input file
                       into smaller chunks

                    * 'count_atgc' which takes a chunk produced by chunk_sequences, and tallies the number of occurrences 
                       of each base in the sequence(s) in the file

                    * 'calc_overall_percentage' which takes the base count subtotals from all count_atgc jobs and calculates 
                      the overall %GC in the sequence(s) in the original input file. The 'calc_overall_percentage' job is 
                      blocked by a semaphore until all count_atgc jobs have completed.

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'chunk_sequences',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
            -parameters => {
                'max_chunk_length'  => 100,                     # amount of sequence, in bases, to include in a single chunk file
                'output_dir'        => '.',                     # directory to store the chunk files
                'output_prefix'     => 'gcpct_pipeline_chunk_', # common prefix for the chunk files
                'output_suffix'     => '.chnk',                 # common suffix for the chunk files

            },
            -input_ids => [ { } ],  # auto-seed one job with default parameters (coming from pipeline-wide parameters or analysis parameters)
            -flow_into => {
                '2->A' => [ 'count_atgc' ],   # will create a semaphored fan of jobs; will use param_stack mechanism to pass parameters around
                'A->1' => [ 'calc_overall_percentage'  ],   # will create a semaphored funnel job to wait for the fan to complete
            },
        },

        {   -logic_name => 'count_atgc',
            -module     => 'Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CountATGC',
            -analysis_capacity  =>  4,  # use per-analysis limiter
            -flow_into => {
 			   1 => ['?accu_name=at_count&accu_address=[]', 
				 '?accu_name=gc_count&accu_address=[]']
            },
        },
        
        {   -logic_name => 'calc_overall_percentage',
            -module     => 'Bio::EnsEMBL::Hive::Examples::GC::RunnableDB::CalcOverallPercentage',
            -flow_into => {
                1 => [ '?table_name=final_result' ], #Flows output into the DB table 'final_result'
            },
        },
     ];
}

1;

