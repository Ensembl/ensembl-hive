#!/usr/bin/env perl
use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use Getopt::Long qw(:config no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Scripts::PeekJob;
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();


sub main {
    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $job_id, $help); 

    GetOptions(

    # Connection parameters:
               'url=s'                        => \$url,
               'reg_conf|regfile|reg_file=s'  => \$reg_conf,
               'reg_type=s'                   => \$reg_type,
               'reg_alias|regname|reg_name=s' => \$reg_alias,
               'nosqlvc'                      => \$nosqlvc,       # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option

    # Task specification parameters:
               'job_id=i'                   => \$job_id,

    # Other commands
               'h|help'                     => \$help,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help || !$job_id) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $pipeline;

    if($url or $reg_alias) {

        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $url,
            -reg_conf                       => $reg_conf,
            -reg_type                       => $reg_type,
            -reg_alias                      => $reg_alias,
            -no_sql_schema_version_check    => $nosqlvc,
        );
        # $pipeline->hive_dba()->dbc->requires_write_access();

    } else {
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
    }

    unless($pipeline->hive_dba) {
        die "ERROR : no database connection, the pipeline could not be accessed\n\n";
    }

    print Bio::EnsEMBL::Hive::Scripts::PeekJob::peek($pipeline, $job_id);
}


__DATA__

=pod

=head1 NAME

peekJob.pl [options]

=head1 DESCRIPTION

peekJob.pl is an eHive component script that allows us to peek into the parameters of a given job.

=head1 USAGE EXAMPLES

        # Check the params for job 123456
    peekJob.pl -url mysql://username:secret@hostname:port/ehive_dbname -job_id 12345

=head1 OPTIONS

=head2 Connection parameters:

=over

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_alias <string>

species/alias name for the eHive DBAdaptor

=item --reg_type <string>

type of the registry entry ("hive", "core", "compara", etc - defaults to "hive")

=item --url <url string>

URL defining where database is located

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

=back

=head2 Task specification parameters:

=over

=item --job_id <id>

which Job (as defined by its database id) to peek at

=back

=head2 Other options:

=over

=item --help

print this help

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut
