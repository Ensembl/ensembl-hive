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

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::Valley;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();
exit(0);


sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $source_line, $username, $meadow_type, $help);

    GetOptions(
                # connect to the database:
            'url=s'                 => \$url,
            'reg_conf|regfile=s'    => \$reg_conf,
            'reg_type=s'            => \$reg_type,
            'reg_alias|regname=s'   => \$reg_alias,
            'nosqlvc'               => \$nosqlvc,       # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option

            'username=s'            => \$username,      # say "-user all" if the pipeline was run by several people
            'source_line=s'         => \$source_line,
            'meadow_type=s'         => \$meadow_type,
            'h|help'                => \$help,
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if ($help) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $hive_dba;
    if($url or $reg_alias) {
        $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
                -url                            => $url,
                -reg_conf                       => $reg_conf,
                -reg_type                       => $reg_type,
                -reg_alias                      => $reg_alias,
                -no_sql_schema_version_check    => $nosqlvc,
        );
        $hive_dba->dbc->requires_write_access();
    } else {
        die "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
    }

    my $queen = $hive_dba->get_Queen;
    my $meadow_2_pid_wid = $queen->fetch_HASHED_FROM_meadow_type_AND_meadow_name_AND_process_id_TO_worker_id();

    my $config = Bio::EnsEMBL::Hive::Utils::Config->new();
    my $valley = Bio::EnsEMBL::Hive::Valley->new($config);

    if( $source_line ) {

        my $meadow = $valley->available_meadow_hash->{$meadow_type || ''} || $valley->get_available_meadow_list()->[0];
        warn "Taking the resource_usage data from the source ( $source_line ), assuming Meadow ".$meadow->signature."\n";

        if(my $report_entries = $meadow->parse_report_source_line( $source_line ) ) {
            $queen->store_resource_usage( $report_entries, $meadow_2_pid_wid->{$meadow->type}{$meadow->cached_name} );
        }

    } else {
        warn "Searching for Workers without known resource_usage...\n";

        my $meadow_2_interval = $queen->interval_workers_with_unknown_usage();

        foreach my $meadow (@{ $valley->get_available_meadow_list() }) {

            warn "\nFinding out the time interval when the pipeline was run on Meadow ".$meadow->signature."\n";

            if(my $our_interval = $meadow_2_interval->{ $meadow->type }{ $meadow->cached_name } ) {
                if(my $report_entries = $meadow->get_report_entries_for_time_interval( $our_interval->{'min_submitted'}, $our_interval->{'max_died'}, $username ) ) {
                    $queen->store_resource_usage( $report_entries, $meadow_2_pid_wid->{$meadow->type}{$meadow->cached_name} );
                }
            } else {
                warn "\tNothing new to store for Meadow ".$meadow->signature."\n";
            }
        }
    }
}

__DATA__

=pod

=head1 NAME

load_resource_usage.pl

=head1 DESCRIPTION

This script obtains resource usage data for your pipeline from the Meadow and stores it in the C<worker_resource_usage> table.
Your Meadow class/plugin has to support offline examination of resources in order for this script to work.

Based on the start time of the first Worker and end time of the last Worker (as recorded in the pipeline database),
it pulls the relevant data out of your Meadow (runs the C<bacct> script in case of LSF), parses the report and stores in the C<worker_resource_usage> table.
You can join this table to the C<worker> table USING(meadow_name,process_id) in the usual MySQL way
to filter by analysis_id, do various stats, etc.

You can optionally provide an an external filename or command to get the data from it (don't forget to append a "|" to the end!)
and then the data will be taken from your source and parsed from there.

=head1 USAGE EXAMPLES

        # Just run it the usual way: query and store the relevant data into "worker_resource_usage" table:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test

        # The same, but assuming another user "someone_else" ran the pipeline:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -username someone_else

        # Assuming the dump file existed. Load the dumped bacct data into "worker_resource_usage" table:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -source long_mult.bacct

        # Provide your own command to fetch and parse the worker_resource_usage data from:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -source "bacct -l -C 2012/01/25/13:33,2012/01/25/14:44 |" -meadow_type LSF

=head1 OPTIONS

=over

=item --help

print this help

=item --url <url string>

URL defining where eHive database is located

=item --username <username>

if it wasn't you who ran the pipeline, the name of that user can be provided

=item --source <filename>

alternative source of worker_resource_usage data. Can be a filename or a pipe-from command.

=item --meadow_type <type>

only used when -source is given. Tells which meadow type the source filename relates to. Defaults to the first available meadow (LOCAL being considered as the last available)

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

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

