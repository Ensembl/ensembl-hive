#!/usr/bin/env perl

# Obtain bacct data for your pipeline from the LSF and store it in lsf_report table

use strict;
use warnings;
use Getopt::Long;

use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::Utils ('script_usage');

main();
exit(0);


sub main {

    my ($url, $bacct_source_line, $lsf_user, $help);

    GetOptions(
               'url=s'                      => \$url,
               'dump|file=s'                => \$bacct_source_line,
               'lu|lsf_user=s'              => \$lsf_user,
               'h|help'                     => \$help,
    );

    if ($help) { script_usage(0); }

    unless( $url ) {
        print "\nERROR : --url is an obligatory parameter for connecting to your database\n\n";
        script_usage(1);
    }

    my $dba = Bio::EnsEMBL::Hive::URLFactory->fetch( $url ) || die "Unable to connect to pipeline database '$url'\n";
    my $dbc = $dba->dbc();

    warn "Creating the 'lsf_report' table if it doesn't exist...\n";
    $dbc->do (qq{
        CREATE TABLE IF NOT EXISTS lsf_report (
            process_id       varchar(40) NOT NULL,
            status           varchar(20) NOT NULL,
            mem              int NOT NULL,
            swap             int NOT NULL,
            exception_status varchar(40) NOT NULL,

            PRIMARY KEY (process_id)

        ) ENGINE=InnoDB;
    });

    if( $bacct_source_line && -r $bacct_source_line ) {

        warn "Parsing given bacct file '$bacct_source_line'...\n";

    } else {

        warn "No bacct information given, finding out the time interval when the pipeline was run...\n";

        my $sth_times = $dbc->prepare( 'SELECT min(born), max(died) FROM worker WHERE meadow_type="LSF"' );
        $sth_times->execute();
        my ($from_time, $to_time) = $sth_times->fetchrow_array();
        $sth_times->finish();

        $from_time=~s/[- ]/\//g;
        $from_time=~s/:\d\d$//;
        $to_time=~s/[- ]/\//g;
        $to_time=~s/:\d\d$//;

        warn "\tfrom=$from_time, to=$to_time\n";

        $lsf_user = $lsf_user           ? "-u $lsf_user"                : '';
        my $tee   = $bacct_source_line  ? "| tee $bacct_source_line"    : '';
        $bacct_source_line = "bacct -l -C $from_time,$to_time $lsf_user $tee |";

        warn 'Will run the following command to obtain '.($tee ? 'and dump ' : '')."bacct information: '$bacct_source_line' (may take a few minutes)\n";
    }

    my $sth_replace = $dbc->prepare( 'REPLACE INTO lsf_report (process_id, status, mem, swap, exception_status) VALUES (?, ?, ?, ?, ?)' );
    {
        local $/ = "------------------------------------------------------------------------------\n\n";
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

                my (@keys)   = split(/\s+/, $lines[@lines-2]);
                my (@values) = split(/\s+/, $lines[@lines-1]);
                my %usage = map { ($keys[$_] => $values[$_]) } (0..@keys-1);

                my ($mem)  = $usage{MEM}  =~ /^(\d+)[KMG]$/;
                my ($swap) = $usage{SWAP} =~ /^(\d+)[KMG]$/;

                #warn "PROC_ID=$process_id, STATUS=$usage{STATUS}, MEM=$usage{MEM}, SWAP=$usage{SWAP}, EXC_STATUS='$exception_status'\n";
                $sth_replace->execute( $process_id, $usage{STATUS}, $mem, $swap, $exception_status );
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

    Based on the start time of the first worker and end time of the last worker (as recorded in pipeline DB)
    it pulls the relevant data out of LSF's 'bacct' database, parses it and stores in 'lsf_report' table.
    You can join this table to 'worker' table USING(process_id) in the usual MySQL way
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

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

