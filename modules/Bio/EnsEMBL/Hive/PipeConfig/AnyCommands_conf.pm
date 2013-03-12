
=pod

=head1 NAME

  Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf -password <your_password>

    seed_pipeline.pl -url $HIVE_URL -logic_name perform_cmd -input_id "{'cmd' => 'gzip pdfs/RondoAllaTurca_Mozart_Am.pdf; sleep 5'}"

    runWorker.pl -url $HIVE_URL

    seed_pipeline.pl -url $HIVE_URL -logic_name perform_cmd -input_id "{'cmd' => 'gzip -d pdfs/RondoAllaTurca_Mozart_Am.pdf.gz ; sleep 4'}"

    runWorker.pl -url $HIVE_URL

=head1 DESCRIPTION

    This is the smallest Hive pipeline example possible.
    The pipeline has only one analysis, which can run any shell command defined in each job by setting its 'cmd' parameter.

=cut


package Bio::EnsEMBL::Hive::PipeConfig::AnyCommands_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');


sub pipeline_analyses {
    return [
        {   -logic_name    => 'perform_cmd',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
        },
    ];
}

1;

