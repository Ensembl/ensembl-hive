
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf -password <your_password>

    seed_pipeline.pl -url <url> -logic_name find_files -input_id "{ 'directory' => 'dumps', 'only_files' => '*.sql' }"

    seed_pipeline.pl -url <url> -logic_name find_files -input_id "{ 'directory' => '$HOME/ncbi_taxonomy', 'gzip_flags' => '-d' }"

=head1 DESCRIPTION

    This is an example pipeline put together from two basic building blocks:

    Analysis_1: JobFactory.pm is used to turn the list of files in a given directory into jobs

        these jobs are sent down the branch #2 into the second analysis

    Analysis_2: SystemCmd.pm is used to run these compression/decompression jobs in parallel.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::CompressFiles_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  Redefines the current pipeline_name. There is also an invisible dependency on o('password') which has to be defined.

=cut

sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },       # inherit other stuff from the base class

        'pipeline_name' => 'compress_files',        # name used by the beekeeper to prefix job names on the farm
    };
}


=head2 pipeline_wide_parameters

    Description : Interface method that should return a hash of pipeline_wide_parameter_name->pipeline_wide_parameter_value pairs.
                  The value doesn't have to be a scalar, can be any Perl structure (will be stringified and de-stringified automagically).

=cut

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class, then add our own stuff

        'gzip_flags'    => '',      # can be set to '-d' for decompression
        'directory'     => '.',     # directory where both source and target files are located
        'only_files'    => '*',     # any wildcard understood by shell
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'find_files'          generates a list of files whose names match the pattern #only_files#
                                            Each job of this analysis will dataflow (create jobs) via branch #2 into 'compress_a_file' analysis.

                    * 'compress_a_file'     actually performs the (un)zipping of the files in parallel

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'find_files',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputcmd'     => 'find #directory# -type f -name "#only_files#"',
                'column_names' => [ 'filename' ],
            },
            -flow_into => {
#                2 => [ 'compress_a_file' ],     # will create a fan of jobs
                2 => { 'compress_a_file' => { 'filename' => '#filename#', 'gzip_flags' => '#gzip_flags#' }, },  # propagate 'gzip_flags' as well
            },
        },

        {   -logic_name    => 'compress_a_file',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'cmd'       => 'gzip #gzip_flags# #filename#',
            },
            -analysis_capacity => 4,            # limit the number of workers that will be performing jobs in parallel
        },
    ];
}

1;

