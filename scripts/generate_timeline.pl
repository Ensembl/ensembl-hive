#!/usr/bin/env perl

# Gets the activity of each analysis along time, in a CSV file

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
use DateTime;
use DateTime::Format::ISO8601;
use List::Util qw(sum max);
use POSIX;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');

main();
exit(0);

sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $help, $start_date, $end_date, $granularity, $skip, $output);

    GetOptions(
                # connect to the database:
            'url=s'                      => \$url,
            'reg_conf|regfile=s'         => \$reg_conf,
            'reg_type=s'                 => \$reg_type,
            'reg_alias|regname=s'        => \$reg_alias,
            'nosqlvc=i'                  => \$nosqlvc,      # using "=i" instead of "!" for consistency with scripts where it is a propagated option

            'start_date=s'               => \$start_date,
            'end_date=s'                 => \$end_date,
            'step=i'                     => \$granularity,
            'output=s'                   => \$output,
            'skip=i'                     => \$skip,
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

    $granularity = 5 unless $granularity;
    $skip = 20 unless $skip;
    my $nothing_title = 'NOTHING';

    my $dbc = $hive_dba->dbc();
    my $dbh = $dbc->db_handle();


    my $sql_index = 'ALTER TABLE worker ADD KEY date_stats (analysis_id, born, died);';

    my $sql_limits = 'SELECT DATE_FORMAT(MIN(born), "%Y-%m-%dT%T"), DATE_FORMAT(MAX(died), "%Y-%m-%dT%T") FROM worker;';
    my $worker_limits = $dbh->selectall_arrayref($sql_limits);
    $start_date = $worker_limits->[0]->[0] unless $start_date;
    warn $start_date;
    $end_date   = $worker_limits->[0]->[1] unless $end_date;
    warn $end_date;

    my $sql_analysis_in_interval = '
        SELECT analysis_id, SUM(TIME_TO_SEC(TIMEDIFF( LEAST(IFNULL(died, "2100-01-01 00:00:00"), ?), GREATEST(born, ?) ))) / (60*?)
        FROM worker
        WHERE analysis_id IS NOT NULL AND born < ? AND (died is NULL OR died >= ?)
        GROUP BY analysis_id';

    my $sql_analysis_names = 'SELECT analysis_id, logic_name FROM analysis_base';
    my $data = $dbh->selectall_arrayref($sql_analysis_names);
    my %name = (map {$_->[0] => $_->[1] } @$data);

    use Data::Dumper;
    #die Dumper \%name;

    $start_date = DateTime::Format::ISO8601->parse_datetime($start_date);
    $end_date   = DateTime::Format::ISO8601->parse_datetime($end_date);

    my $max_workers = 0;
    my @data_timings = ();
    my %tot_analysis = ();

    my $curr_date = $start_date;
    while ($curr_date < $end_date) {
        my $next_date = $curr_date->clone();
        $next_date->add(minutes => $granularity);

        my $d1 = $curr_date->datetime;
        my $d2 = $next_date->datetime;
        $d1 =~ s/T/ /;
        $d2 =~ s/T/ /;
        my $timings_interval = $dbh->selectall_arrayref($sql_analysis_in_interval, undef, $d2, $d1, $granularity, $d2, $d1);
        my %hash_interval = (map {$_->[0] => $_->[1] } @$timings_interval);

        my $sum_a = sum(0, values %hash_interval);
        map {$tot_analysis{$_} += $hash_interval{$_}} keys %hash_interval;

        $max_workers = $sum_a if ($sum_a > $max_workers);
        push @data_timings, [$curr_date->datetime, $sum_a, \%hash_interval];
        #warn $d1, ' ', $sum_a, ' ', $max_workers;

        $curr_date = $next_date;
    }
    warn $max_workers;
    $max_workers = 100*ceil($max_workers /100)-10;
#    output_csv(\%tot_analysis, \%name, \@data_timings, $skip);
#}

#sub output_csv {
#    my %tot_analysis = %{ (shift) };
#    my %name         = %{ (shift) };
#    my @data_timings = @{ (shift) };
#    my $skip         = shift;
    
    my $total_total = sum(values %tot_analysis);
#    my $max_workers = max(map {$_->[1]} @data_timings);
#    warn $max_workers;
#    #$max_workers = 1000*ceil(max(map {$_->[1]} @data_timings)
#    #$max_workers /1000)-100;
#    my $max_workers = 0;

    my @sorted_analysis_ids = sort {($tot_analysis{$b} <=> $tot_analysis{$a}) || (lc $name{$a} cmp lc $name{$b})} keys %tot_analysis;
    my $s = 0;
    my @filtered_analysis_ids = grep {my $pre_s = $s; $s += $tot_analysis{$_}/$total_total; $pre_s < .995} @sorted_analysis_ids;
    #warn Dumper \@sorted_analysis_ids;
    print join("\t", 'analysis', $nothing_title, map {$name{$_}} @filtered_analysis_ids), "\n";
    print join("\t", 'total', $total_total, map {$tot_analysis{$_}} @filtered_analysis_ids), "\n";
    print join("\t", 'proportion', '0', map {$tot_analysis{$_}/$total_total} @filtered_analysis_ids), "\n";
    $s = 0;
    print join("\t", 'cum_proportion', '0', map {$s+=$tot_analysis{$_}/$total_total} @filtered_analysis_ids), "\n";

    my @buffer = ();
    foreach my $row (@data_timings) {
        my $str = join("\t", $row->[0], $row->[1] ? 0 : $max_workers, map {$row->[2]->{$_} || 0} @filtered_analysis_ids)."\n";
        if ($row->[1]) {
            if (@buffer) {
                my $n = scalar(@buffer);
                if ($n > $skip) {
                    splice(@buffer, int($skip / 2), $n-$skip);
                }
                foreach my $old_str (@buffer) {
                    print $old_str;
                }
                @buffer = ();
            }
            print $str;
        } else {
            push @buffer, $str;
        }
    }

    #my $pipeline_name = $hive_dba->get_MetaAdaptor->fetch_value_by_key( 'hive_pipeline_name' );
    my $gnuplot_intro = "
set terminal png size 1400, 800
set key outside right
set style fill solid
set xdata time
set timefmt '%Y-%m-%dT%H:%M:%S'
set format x '%b %d'
set ytics 200
set xlabel 'Profile of $url from $start_date to $end_date'
set ylabel 'Number of workers'

";


    print $gnuplot_intro;
    foreach my $i (1..scalar(@filtered_analysis_ids)) {
        printf("set style line %d linetype %d pointtype 0 linewidth 1 linecolor %d\n", $i, $i, $i);
    }
    my @plot_info = ();
    push @plot_info, sprintf(" 'prof_prot.csv' using 1:2 t '$nothing_title' w lines linestyle 0 ");
    foreach my $i (reverse 1..scalar(@filtered_analysis_ids)) {
        push @plot_info, sprintf(" 'prof_prot.csv' using 1:(%s) t '%s' w filledcurves x1 linestyle %d ", join('+', map {"\$$_"} 3..($i+2)), $name{$filtered_analysis_ids[$i-1]}, $i);
    }
    print "plot ['$start_date':'$end_date'][:] ", join(',', @plot_info), "\n";

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
    -start_date <date>      : minimal start date of a job (the format is '2012/01/25/13:46')
    -end_date <date>        : maximal end date of a job (the format is '2012/01/25/13:46')

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

