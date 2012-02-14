#!/usr/bin/env perl

# Obtain bacct data for your pipeline from the LSF and store it in lsf_report table

use strict;
use warnings;
use Getopt::Long;
use Bio::EnsEMBL::Hive::URLFactory;

my ($url, $infile, $lsf_user);

GetOptions(
           'url=s'                      => \$url,
           'infile=s'                   => \$infile,
           'lsf_user=s'                 => \$lsf_user,
);

unless( $url ) {
    die "-url is an obligatory parameter for connecting to your database";
}

my $dba = Bio::EnsEMBL::Hive::URLFactory->fetch( $url );
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

if( $infile ) {

    warn "Parsing bacct file '$infile'...\n";

} else {

    warn "No bacct file given, finding out the time interval when the pipeline was run...\n";

    my $sth_times = $dbc->prepare( 'SELECT min(born), max(died) FROM worker WHERE meadow_type="LSF"' );
    $sth_times->execute();
    my ($from_time, $to_time) = $sth_times->fetchrow_array();
    $sth_times->finish();

    $from_time=~s/[- ]/\//g;
    $from_time=~s/:\d\d$//;
    $to_time=~s/[- ]/\//g;
    $to_time=~s/:\d\d$//;

    warn "\tfrom=$from_time, to=$to_time\n";

    $lsf_user = $lsf_user ? "-u $lsf_user" : '';
    $infile = "bacct -C $from_time,$to_time $lsf_user -l |";

    warn "Will run the following command to obtain bacct information: '$infile' (may take a few minutes)\n";
}

my $sth_replace = $dbc->prepare( 'REPLACE INTO lsf_report (process_id, status, mem, swap, exception_status) VALUES (?, ?, ?, ?, ?)' );
{
    local $/ = "------------------------------------------------------------------------------\n\n";
    open(my $bacct_file, $infile);
    my $record = <$bacct_file>; # skip the header

    for my $record (<$bacct_file>) {
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

    close $bacct_file;
}
$sth_replace->finish();
warn "\nReport has been loaded into pipeline's lsf_report table. Enjoy.\n";

