#!/usr/bin/env perl

# A generic script for creating eHive pipelines from PipeConfig module files (see below for docs)

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
use Pod::Usage;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module');
use Bio::EnsEMBL::Hive::Scripts::InitPipeline;

use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

sub main {
    my $deprecated_option   = {};
    my $tweaks              = [];
    my $help;

    GetOptions(
        'analysis_topup!'   => \$deprecated_option->{'analysis_topup'},     # always on
        'job_topup!'        => \$deprecated_option->{'job_topup'},          # never, use seed_pipeline.pl
        'tweak|SET=s@'      => \$tweaks,
        'DELETE=s'          => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'#'; },
        'SHOW=s'            => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'?'; },
	'h|help!'           => \$help,
    );

    if ($help) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    if($deprecated_option->{'job_topup'}) {
        die "-job_topup mode has been discontinued. Please use seed_pipeline.pl instead.\n";
    }
    if($deprecated_option->{'analysis_topup'}) {
        die "-analysis_topup has been deprecated. Please note this script now *always* runs in -analysis_topup mode.\n";
    }

    
    my $file_or_module = shift @ARGV or die "ERROR: Must provide a PipeConfig name on the command-line\n";

    Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module, $tweaks);
}

main();

__DATA__

=pod

=head1 NAME

init_pipeline.pl

=head1 SYNOPSIS

    init_pipeline.pl <config_module_or_filename> [<options_for_this_particular_pipeline>]

=head1 DESCRIPTION

init_pipeline.pl is a generic script that is used to initialise eHive pipelines (i..e create and setup the database) from PipeConfig configuration modules.

=head1 USAGE EXAMPLES

        # get this help message:
    init_pipeline.pl

        # initialise a generic eHive pipeline:
    init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <yourpassword>

        # initialise the long multiplicaton pipeline by supplying not only mandatory but also optional data:
        #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive/PipeConfig) :
    init_pipeline.pl LongMult_conf -password <yourpassword> -first_mult 375857335 -second_mult 1111333355556666 

=head1 OPTIONS

=over

=item --hive_force_init <0|1>

If set to 1, forces the (re)creation of the eHive database even if a previous version of it is present in the server.

=item --hive_no_init <0|1>

If set to 1, does not run the pipeline_create_commands section of the pipeline. Useful to "top-up" an existing database.

=item --hive_debug_init <0|1>

If set to 1, will show the objects (analyses, data-flow rules, etc) that are parsed from the PipeConfig file.

=item --tweak <string>

Apply tweaks to the pipeline. See tweak_pipeline.pl for details of tweaking syntax

=item --DELETE

Delete pipeline parameter (shortcut for tweak DELETE)

=item --SHOW

Show  pipeline parameter  (shortcut for tweak SHOW)

=item -h, --help

Show this help message

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

