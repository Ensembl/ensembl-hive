#!/usr/bin/env perl

# Obtain bacct data for your pipeline from the LSF and store it in 'worker_resource_usage' table

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
use Bio::EnsEMBL::Hive::Meadow::LSF;

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

    my $this_lsf_farm = Bio::EnsEMBL::Hive::Meadow::LSF::name()
        or die "Cannot find the name of the current farm.\n";

    my $report_entries;

    if( $source_line ) {

        $report_entries = Bio::EnsEMBL::Hive::Meadow::LSF->parse_report_source_line( $source_line );

    } else {

        warn "No bacct information given, finding out the time interval when the pipeline was run on '$this_lsf_farm' ...\n";

        my $meadow_to_interval = $queen->interval_workers_with_unknown_usage();
        my $our_interval = $meadow_to_interval->{ 'LSF' }{ $this_lsf_farm };

        my ($from_time, $to_time);

        if( $our_interval ) {
            ($from_time, $to_time) = @$our_interval{ 'min_born', 'max_died' };

            $report_entries = Bio::EnsEMBL::Hive::Meadow::LSF->get_report_entries_for_time_interval( $from_time, $to_time, $username );
        } else {
            die "Usage information for this meadow has already been loaded, exiting...\n";
        }
    }

    if($report_entries and %$report_entries) {
        my $processid_2_workerid = $queen->fetch_by_meadow_type_AND_meadow_name_HASHED_FROM_process_id_TO_worker_id( 'LSF', $this_lsf_farm );

        $queen->store_resource_usage( $report_entries, $processid_2_workerid );
    }
}

__DATA__

=pod

=head1 NAME

    lsf_report.pl

=head1 DESCRIPTION

    This script is used for offline examination of resources used by a Hive pipeline running on LSF
    (the script is [Pp]latform-dependent).

    Based on the start time of the first Worker and end time of the last Worker (as recorded in pipeline DB),
    it pulls the relevant data out of LSF's 'bacct' database, parses it and stores in 'worker_resource_usage' table.
    You can join this table to 'worker' table USING(meadow_name,process_id) in the usual MySQL way
    to filter by analysis_id, do various stats, etc.

    You can optionally provide an an external filename or command to get the data from it (don't forget to append a '|' to the end!)
    and then the data will be taken from your source and parsed from there.

=head1 USAGE EXAMPLES

        # Just run it the usual way: query 'bacct' and load the relevant data into 'worker_resource_usage' table:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test

        # The same, but assuming LSF user someone_else ran the pipeline:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -username someone_else

        # Assuming the dump file existed. Load the dumped bacct data into 'worker_resource_usage' table:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -source long_mult.bacct

        # Provide your own command to fetch and parse the worker_resource_usage data from:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -source "bacct -l -C 2012/01/25/13:33,2012/01/25/14:44 |"

=head1 OPTIONS

    -help                   : print this help
    -url <url string>       : url defining where hive database is located
    -username <username>    : if it wasn't you who ran the pipeline, LSF user name of that user can be provided
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

