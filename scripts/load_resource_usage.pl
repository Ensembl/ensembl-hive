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


use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');
use Bio::EnsEMBL::Hive::Valley;

main();
exit(0);


sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $source_line, $username, $help);

    GetOptions(
                # connect to the database:
            'url=s'                 => \$url,
            'reg_conf|regfile=s'    => \$reg_conf,
            'reg_type=s'            => \$reg_type,
            'reg_alias|regname=s'   => \$reg_alias,
            'nosqlvc=i'             => \$nosqlvc,       # using "=i" instead of "!" for consistency with scripts where it is a propagated option

            'username=s'            => \$username,      # say "-user all" if the pipeline was run by several people
            'source_line=s'         => \$source_line,
            'h|help'                => \$help,
    );

    if ($help) { script_usage(0); }

    my $hive_dba;
    if($url or $reg_alias) {
        $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
                -url                            => $url,
                -reg_conf                       => $reg_conf,
                -reg_type                       => $reg_type,
                -reg_alias                      => $reg_alias,
                -no_sql_schema_version_check    => $nosqlvc,
        );
    } else {
        warn "\nERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified\n";
        script_usage(1);
    }

    my $queen = $hive_dba->get_Queen;
    my $meadow_2_pid_wid = $queen->fetch_HASHED_FROM_meadow_type_AND_meadow_name_AND_process_id_TO_worker_id();

    my $valley = Bio::EnsEMBL::Hive::Valley->new();

    if( $source_line ) {

        my $meadow = $valley->get_available_meadow_list()->[0];
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
                if(my $report_entries = $meadow->get_report_entries_for_time_interval( $our_interval->{'min_born'}, $our_interval->{'max_died'}, $username ) ) {
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

    This script obtains resource usage data for your pipeline from the Meadow and stores it in 'worker_resource_usage' table.
    Your Meadow class/plugin has to support offline examination of resources in order for this script to work.

    Based on the start time of the first Worker and end time of the last Worker (as recorded in pipeline DB),
    it pulls the relevant data out of your Meadow (runs 'bacct' script in case of LSF), parses the report and stores in 'worker_resource_usage' table.
    You can join this table to 'worker' table USING(meadow_name,process_id) in the usual MySQL way
    to filter by analysis_id, do various stats, etc.

    You can optionally provide an an external filename or command to get the data from it (don't forget to append a '|' to the end!)
    and then the data will be taken from your source and parsed from there.

=head1 USAGE EXAMPLES

        # Just run it the usual way: query and store the relevant data into 'worker_resource_usage' table:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test

        # The same, but assuming another user 'someone_else' ran the pipeline:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -username someone_else

        # Assuming the dump file existed. Load the dumped bacct data into 'worker_resource_usage' table:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -source long_mult.bacct

        # Provide your own command to fetch and parse the worker_resource_usage data from:
    load_resource_usage.pl -url mysql://username:secret@hostname:port/long_mult_test -source "bacct -l -C 2012/01/25/13:33,2012/01/25/14:44 |"

=head1 OPTIONS

    -help                   : print this help
    -url <url string>       : url defining where hive database is located
    -username <username>    : if it wasn't you who ran the pipeline, the name of that user can be provided
    -source <filename>      : alternative source of worker_resource_usage data. Can be a filename or a pipe-from command.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

