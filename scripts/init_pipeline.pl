#!/usr/bin/env perl

# A generic script for creating Hive pipelines from PipeConfig module files (see below for docs)

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long qw(:config pass_through no_auto_abbrev);
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module');
use Bio::EnsEMBL::Hive::Scripts::InitPipeline;

sub main {
    my %deprecated_option = ();
    GetOptions( \%deprecated_option,
        'analysis_topup!',  # always on
        'job_topup!',       # never, use seed_pipeline.pl
    );

    if($deprecated_option{'job_topup'}) {
        die "-job_topup mode has been discontinued. Please use seed_pipeline.pl instead.\n";
    }
    if($deprecated_option{'analysis_topup'}) {
        die "-analysis_topup has been deprecated. Please note this script now *always* runs in -analysis_topup mode.\n";
    }

    my $file_or_module = shift @ARGV or script_usage(0);

    return Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module);
}

main();

__DATA__

=pod

=head1 NAME

    init_pipeline.pl

=head1 SYNOPSIS

    init_pipeline.pl <config_module_or_filename> [<options_for_this_particular_pipeline>]

=head1 DESCRIPTION

    init_pipeline.pl is a generic script that is used to create+setup=initialize eHive pipelines from PipeConfig configuration modules.

=head1 USAGE EXAMPLES

        # get this help message:
    init_pipeline.pl

        # initialize a generic eHive pipeline:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <yourpassword>

        # initialize the long multiplicaton pipeline by supplying not only mandatory but also optional data:
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive/PipeConfig) :
    init_pipeline.pl LongMult_conf -password <yourpassword> -first_mult 375857335 -second_mult 1111333355556666 

=head1 OPTIONS

    -hive_force_init :   If set to 1, forces the (re)creation of the hive database even if a previous version of it is present in the server.

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

