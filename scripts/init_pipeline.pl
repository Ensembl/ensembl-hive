#!/usr/bin/env perl

# A generic loader of hive pipelines.
#
# Because all of the functionality is hidden in Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf
# you can create pipelines by calling the right methods of HiveGeneric_conf directly,
# so this script is just a commandline wrapper that can conveniently find modules by their filename.

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module');

sub main {
    my $file_or_module = shift @ARGV or script_usage(0);

    my $config_module = load_file_or_module( $file_or_module );

    my $config_object = $config_module->new();
    $config_object->process_options();
    $config_object->run();
}

main();

__DATA__

=pod

=head1 NAME

    init_pipeline.pl

=head1 SYNOPSIS

    init_pipeline.pl <config_module_or_filename> [-help | [-analysis_topup | -job_topup] <options_for_this_particular_pipeline>]

=head1 DESCRIPTION

    init_pipeline.pl is a generic script that is used to create+setup=initialize eHive pipelines from PipeConfig configuration modules.

=head1 USAGE EXAMPLES

        # get this help message:
    init_pipeline.pl

        # initialize a generic eHive pipeline:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <yourpassword>

        # see what command line options are available when initializing long multiplication example pipeline
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive) :
    init_pipeline.pl PipeConfig/LongMult_conf -help

        # initialize the long multiplicaton pipeline by supplying not only mandatory but also optional data:
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive/PipeConfig) :
    init_pipeline.pl LongMult_conf -password <yourpassword> -first_mult 375857335 -second_mult 1111333355556666 

=head1 OPTIONS

    -help            :   Gets this help message and exits

    -analysis_topup  :   A special initialization mode when (1) pipeline_create_commands are switched off and (2) only newly defined analyses are added to the database
                         This mode is only useful in the process of putting together a new pipeline.

    -job_topup       :   Another special initialization mode when only jobs are created - no other structural changes to the pipeline are acted upon.

    -hive_force_init :   If set to 1, forces the (re)creation of the hive database even if a previous version of it is present in the server.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

