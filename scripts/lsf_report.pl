#!/usr/bin/env perl

# Obtain bacct data for your pipeline from the LSF and store it in lsf_report table

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');
use Bio::EnsEMBL::Hive::Meadow::LSF;

main();
exit(0);


sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $bacct_source_line, $lsf_user, $help, $start_date, $end_date);

    GetOptions(
                # connect to the database:
            'url=s'                      => \$url,
            'reg_conf|regfile=s'         => \$reg_conf,
            'reg_type=s'                 => \$reg_type,
            'reg_alias|regname=s'        => \$reg_alias,
            'nosqlvc=i'                  => \$nosqlvc,      # using "=i" instead of "!" for consistency with scripts where it is a propagated option

            'dump|file=s'                => \$bacct_source_line,
            'lu|lsf_user=s'              => \$lsf_user,
            'sd|start_date=s'            => \$start_date,
            'ed|end_date=s'              => \$end_date,
            'h|help'                     => \$help,
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

    my $dbc = $hive_dba->dbc();

    warn "Creating the 'lsf_report' table if it doesn't exist...\n";
    $dbc->do (qq{
        CREATE TABLE IF NOT EXISTS lsf_report (
            meadow_name      varchar(255) NOT NULL,
            process_id       varchar(255) NOT NULL,
            status           varchar(20) NOT NULL,
            mem_megs         float NOT NULL,
            swap_megs        float NOT NULL,
            pending_sec      integer NOT NULL,
            cpu_sec          float NOT NULL,
            lifespan_sec     integer NOT NULL,
            exception_status varchar(40) NOT NULL,

            PRIMARY KEY (meadow_name,process_id)

        ) ENGINE=InnoDB;
    });

    warn "Creating the 'lsf_usage' view if it doesn't exist...\n";
    $dbc->do (qq{
        CREATE OR REPLACE VIEW lsf_usage AS
            SELECT CONCAT(logic_name,'(',analysis_id,')') analysis,
                   CONCAT(rc.name,'(',rc.resource_class_id,')') resource_class,
                   count(*) workers,
                   min(mem_megs), avg(mem_megs), max(mem_megs),
                   min(swap_megs), avg(swap_megs), max(swap_megs)
            FROM analysis_base
            JOIN resource_class rc USING(resource_class_id)
            LEFT JOIN worker w USING(analysis_id)
            LEFT JOIN lsf_report USING (meadow_name, process_id)
            WHERE w.meadow_type='LSF'
            GROUP BY analysis_id
            ORDER BY analysis_id;
    });

    my $this_lsf_farm = Bio::EnsEMBL::Hive::Meadow::LSF::name();
    die "Cannot find the name of the current farm.\n" unless $this_lsf_farm;

    if( $bacct_source_line && -r $bacct_source_line ) {

        warn "Parsing given bacct file '$bacct_source_line'...\n";

    } else {

        warn "No bacct information given, finding out the time interval when the pipeline was run on '$this_lsf_farm' ...\n";

        my $offset_died_expression = ($dbc->driver eq 'sqlite')
                        ? "datetime(max(died), '+1 minute')"
                        : "FROM_UNIXTIME(UNIX_TIMESTAMP(max(died))+60)";

        my $sth_times = $dbc->prepare( "SELECT min(born), $offset_died_expression FROM worker WHERE meadow_type='LSF' AND meadow_name='$this_lsf_farm' AND status='DEAD'" );
        $sth_times->execute();
        my ($from_time, $to_time) = $sth_times->fetchrow_array();
        $sth_times->finish();

        unless(defined($from_time) and defined($to_time)) {
            die "There seems to be no information on workers, exiting...\n";
        }

        if (defined $start_date) {
            die "start_date must be in a format like '2012/01/25/13:46'" unless $start_date =~ /^\d{4}\/\d{2}\/\d{2}\/\d{2}:\d{2}$/;
            $from_time = $start_date;
        } else {
            $from_time=~s/[- ]/\//g;
            $from_time=~s/:\d\d$//;
        }

        if (defined $end_date) {
            die "end_date must be in a format like '2012/01/25/13:46'" unless $end_date =~ /^\d{4}\/\d{2}\/\d{2}\/\d{2}:\d{2}$/;
            $to_time = $end_date;
        } else {
            $to_time=~s/[- ]/\//g;
            $to_time=~s/:\d\d$//;
        }

        warn "\tfrom=$from_time, to=$to_time\n";

        $lsf_user = $lsf_user           ? "-u $lsf_user"                : '';
        my $tee   = $bacct_source_line  ? "| tee $bacct_source_line"    : '';
        $bacct_source_line = "bacct -l -C $from_time,$to_time $lsf_user $tee |";

        warn 'Will run the following command to obtain '.($tee ? 'and dump ' : '')."bacct information: '$bacct_source_line' (may take a few minutes)\n";
    }

    my $sth_replace = $dbc->prepare( 'REPLACE INTO lsf_report (meadow_name, process_id, status, mem_megs, swap_megs, pending_sec, cpu_sec, lifespan_sec, exception_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)' );
    {
        local $/ = "------------------------------------------------------------------------------\n\n";
        my %units_converter = ( 'K' => 1.0/1024, 'M' => 1, 'G' => 1024, 'T' => 1024*1024 );

        open(my $bacct_fh, $bacct_source_line);
        my $record = <$bacct_fh>; # skip the header

        for my $record (<$bacct_fh>) {
            chomp $record;

            # warn "RECORD:\n$record";

            my @lines = split(/\n/, $record);
            if( my ($process_id) = $lines[0]=~/^Job <(\d+(?:\[\d+\])?)>/) {

                my $exception_status = '';
                foreach (@lines) {
                    if(/^\s*EXCEPTION STATUS:\s*(.*?)\s*$/) {
                        $exception_status = $1;
                        $exception_status =~s/\s+/;/g;
                    }
                }

                my (@keys)   = split(/\s+/, ' '.$lines[@lines-2]);
                my (@values) = split(/\s+/, ' '.$lines[@lines-1]);
                my %usage = map { ($keys[$_] => $values[$_]) } (0..@keys-1);

                my ($mem_in_units, $mem_unit)   = $usage{'MEM'}  =~ /^([\d\.]+)([KMGT])$/;
                my ($swap_in_units, $swap_unit) = $usage{'SWAP'} =~ /^([\d\.]+)([KMGT])$/;

                my $mem_megs    = $mem_in_units  * $units_converter{$mem_unit};
                my $swap_megs   = $swap_in_units * $units_converter{$swap_unit};

                #warn join(', ', map {sprintf('%s=%s', $_, $usage{$_})} (sort keys %usage)), "\n";
                $sth_replace->execute( $this_lsf_farm, $process_id, $usage{STATUS}, $mem_megs, $swap_megs, $usage{WAIT}, $usage{CPU_T}, $usage{TURNAROUND}, $exception_status );
            }
        }

        close $bacct_fh;
    }
    $sth_replace->finish();
    warn "\nReport has been loaded into pipeline's lsf_report table. Enjoy.\n";

}

__DATA__

=pod

=head1 NAME

    lsf_report.pl

=head1 DESCRIPTION

    This script is used for offline examination of resources used by a Hive pipeline running on LSF
    (the script is [Pp]latform-dependent).

    Based on the command-line parameters 'start_date' and 'end_date', or on the start time of the first
    worker and end time of the last worker (as recorded in pipeline DB), it pulls the relevant data out
    of LSF's 'bacct' database, parses it and stores in 'lsf_report' table.
    You can join this table to 'worker' table USING(meadow_name,process_id) in the usual MySQL way
    to filter by analysis_id, do various stats, etc.

    You can optionally ask the script to dump the 'bacct' database in a dump file,
    or fill in the 'lsf_report' table from an existing dump file (most time is taken by querying bacct).

    Please note the script may additionally pull information about LSF processes that you ran simultaneously
    with running the pipeline. It is easy to ignore them by joining into 'worker' table.

=head1 USAGE EXAMPLES

        # Just run it the usual way: query 'bacct' and load the relevant data into 'lsf_report' table:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test

        # The same, but assuming LSF user someone_else ran the pipeline:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -lsf_user someone_else

        # Assuming the dump file existed. Load the dumped bacct data into 'lsf_report' table:
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -dump long_mult.bacct

        # Assuming the dump file did not exist. Query 'bacct', dump the data into a file and load it into 'lsf_report':
    lsf_report.pl -url mysql://username:secret@hostname:port/long_mult_test -dump long_mult_again.bacct

=head1 OPTIONS

    -help                   : print this help
    -url <url string>       : url defining where hive database is located
    -dump <filename>        : a filename for bacct dump. It will be read from if the file exists, and written to otherwise.
    -lsf_user <username>    : if it wasn't you who ran the pipeline, LSF user name of that user can be provided
    -start_date <date>      : minimal start date of a job (the format is '2012/01/25/13:46')
    -end_date <date>        : maximal end date of a job (the format is '2012/01/25/13:46')

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

