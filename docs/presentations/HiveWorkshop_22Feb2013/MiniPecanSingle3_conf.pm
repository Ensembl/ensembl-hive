
=pod

=head1 NAME

  MiniPecanSingle3_conf

=head1 SYNOPSIS

    init_pipeline.pl MiniPecanSingle3_conf -password <your_password>

    init_pipeline.pl MiniPecanSingle3_conf -hive_driver sqlite -password <FOO>

=head1 DESCRIPTION

    This is an example pipeline put together from basic building blocks:

    Analysis_1: SystemCmd.pm is used to run Pecan on a set of files

        the job is sent down the branch #1 into the second analysis

    Analysis_2: SystemCmd.pm is used to run gerp_col on the resulting alignment

        the job is sent down the branch #1 into the third analysis

    Analysis_3: SystemCmd.pm is used to run gerp_elem on the GERP scores

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package MiniPecanSingle3_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines three options:
                    o('capacity')   defines how many files can be run in parallel
                
                  There are rules dependent on two options that do not have defaults (this makes them mandatory):
                    o('password')           your read-write password for creation and maintenance of the hive database

=cut

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },             # inherit other stuff from the base class

        'pipeline_name' => 'mini_pecan_single3',          # name used by the beekeeper to prefix job names on the farm

    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'pecan'  aligns sequences with Pecan
                      Each job of this analysis will dataflow (create jobs) via branch #1 into 'gerp_col' analysis.

                    * 'gerp_col' runs gerp_col on Pecan output
                      Each job of this analysis will dataflow (create jobs) via branch #1 into 'gerp_elem' analysis.

                    * 'gerp_elem' runs gerp_elem on gerp_col output

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [

        ## First analysis: PECAN
        {   -logic_name => 'pecan',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                # The cmd parameter is required by the SystemCmd module. It defines the command line to be run.
                # Note that some values are written between #hashes#. Those will be subtituted by the corresponding input values
                'cmd'     => 'java -cp /soft/pecan_v0.8/pecan_v0.8.jar bp.pecan.Pecan -E "#tree_string#" -F #input_files# -G #msa_file#',
            },
            
            -input_ids  => [
                # Each input_id is a new job for this analysis. Here we are defining the input_files and the msa_file for
                # the first and only job.
                {
                  'tree_string' => '((((HUMAN,(MOUSE,RAT)),COW),OPOSSUM),CHICKEN);',
                  'input_files' => 'human.fa mouse.fa rat.fa cow.fa opossum.fa chicken.fa',
                  'msa_file'    => "pecan3.mfa",
                  'chr_name'    => "chr13",
                  'chr_start'   => "32878016",
                },
            ],
            -flow_into => {
                # dataflow rule. Once a 'pecan' job is done, it will create a new 'gerp_col' and
                # a new 'gerp_elem' job.
                # Using the input_template, we are setting the input_file for the other two analyses
                '1->A' => { 'gerp_col' => {'input_file' => '#msa_file#'} },
                'A->1' => { 'gerp_elem' => {'input_file' => '#msa_file#.rates',
                                            'chr_name' => '#chr_name#',
                                            'chr_start' => '#chr_start#'}
                                           },
            },
        },



        ## Second analysis: GERP_COL
        {   -logic_name => 'gerp_col',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                # In this case, #msa_file# comes from the parent 'pecan' job.
                'cmd'         => 'gerpcol -t tree.nw -f #input_file# -a -e HUMAN',
            },
        },


        ## Third analysis: GERP_ELEM
        {   -logic_name => 'gerp_elem',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'cmd'   => 'gerpelem -f #input_file# -c #chr_name# -s #chr_start# -x .bed',
            },
        },

    ];
}


1;

