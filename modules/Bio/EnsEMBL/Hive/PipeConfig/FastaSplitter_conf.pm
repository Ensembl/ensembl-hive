
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::FastaSplitter_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::FastaSplitter_conf -inputfile reference.fasta -chunks_dir reference_chunks

=cut

package Bio::EnsEMBL::Hive::PipeConfig::FastaSplitter_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


sub default_options {
    my ($self) = @_;
    return {
        %{ $self->SUPER::default_options() },               # inherit other stuff from the base class

        'pipeline_name' => 'split_fasta',                   # name used by the beekeeper to prefix job names on the farm

            # runnable-specific parameters' defaults:
        'max_chunk_length'  => 500000,
        'output_prefix'     => 'chunk_number_',
        'output_suffix'     => '.fasta',

        'chunks_dir'        => 'fasta_split_chunks',
    };
}


sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

        'mkdir -p '.$self->o('chunks_dir'),
    ];
}


sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'split_fasta',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::FastaFactory',
            -input_ids => [ {
                'inputfile'         => $self->o('inputfile'),
                'max_chunk_length'  => $self->o('max_chunk_length'),
                'output_prefix'     => $self->o('chunks_dir').'/'.$self->o('output_prefix'),
                'output_suffix'     => $self->o('output_suffix'),
            } ],
            -flow_into => {
                2 => [ 'align' ],   # will create a fan of jobs
            },
        },

        {   -logic_name    => 'align',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
        },
    ];
}

1;

