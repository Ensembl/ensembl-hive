#!/usr/bin/env perl

# Gets the activity of each analysis along time, in a CSV file or in an image (see list of formats supported by GNUplot)

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
use List::Util qw(sum);
use POSIX;
use Data::Dumper;

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');

no warnings qw{qw};

main();
exit(0);

sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $help, $start_date, $end_date, $output, $top, $logscale);

    GetOptions(
                # connect to the database:
            'url=s'                      => \$url,
            'reg_conf|regfile=s'         => \$reg_conf,
            'reg_type=s'                 => \$reg_type,
            'reg_alias|regname=s'        => \$reg_alias,
            'nosqlvc=i'                  => \$nosqlvc,      # using "=i" instead of "!" for consistency with scripts where it is a propagated option

            'start_date=s'               => \$start_date,
            'end_date=s'                 => \$end_date,
            'top=f'                      => \$top,
            'log=i'                      => \$logscale,
            'output=s'                   => \$output,
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

    # Palette generated with R: c(brewer.pal(9, "Set1"), brewer.pal(12, "Set3")). #FFFFB3 is removed because it is too close to white
    my @palette = qw(#E41A1C #377EB8 #4DAF4A #984EA3 #FF7F00 #FFFF33 #A65628 #F781BF #999999     #8DD3C7 #BEBADA #FB8072 #80B1D3 #FDB462 #B3DE69 #FCCDE5 #D9D9D9 #BC80BD #CCEBC5 #FFED6F    #2F4F4F);

    my %terminal_mapping = (
        'emf' => 'emf',
        'png' => 'png',
        'svg' => 'svg',
        'jpg' => 'jpeg',
        'gif' => 'gif',
        'ps'  => 'postscript eps enhanced color',
        'pdf' => 'pdf color enhanced',
    );
    my $gnuplot_terminal = undef;
    if ($output and $output =~ /\.(\w+)$/) {
        $gnuplot_terminal = $1;
        die "The format '$gnuplot_terminal' is not currently supported." if not exists $terminal_mapping{$gnuplot_terminal};
        require Chart::Gnuplot;

    }


    my $dbh = $hive_dba->dbc->db_handle();

    # Get the events from the database
    my %events = ();
    {
        my @tmp_dates = @{$dbh->selectall_arrayref('SELECT DATE_FORMAT(born, "%Y-%m-%dT%T"), analysis_id, 1 FROM worker WHERE analysis_id IS NOT NULL')};
        push @tmp_dates, @{$dbh->selectall_arrayref('SELECT DATE_FORMAT(died, "%Y-%m-%dT%T"), analysis_id, -1 FROM worker WHERE analysis_id IS NOT NULL')};
        warn scalar(@tmp_dates), " events\n";

        foreach my $db_entry (@tmp_dates) {
            my ($event_date, $analysis_id, $offset) = @$db_entry;
            $events{$event_date}{$analysis_id} += $offset;
        }
    }
    my @event_dates = sort {$a cmp $b} (keys %events);
    warn scalar(@event_dates), " dates\n";

    my $sql_analysis_names = 'SELECT analysis_id, logic_name FROM analysis_base';
    my @analysis_data = @{$dbh->selectall_arrayref($sql_analysis_names)};
    my %name = (map {$_->[0] => $_->[1] } @analysis_data);
    warn scalar(@analysis_data), " analysis\n";

    my $max_workers = 0;
    my @data_timings = ();
    my %tot_analysis = ();

    my $num_curr_workers = 0;
    my %hash_curr_workers = (map {$_->[0] => 0 } @analysis_data);

    foreach my $event_date (@event_dates) {

        last if $end_date and ($event_date gt $end_date);

        my $topup_hash = $events{$event_date};
        foreach my $analysis_id (keys %$topup_hash) {
            $hash_curr_workers{$analysis_id} += $topup_hash->{$analysis_id};
            $num_curr_workers += $topup_hash->{$analysis_id};
        }
        die if sum(values %hash_curr_workers) != $num_curr_workers;

        next if $start_date and ($event_date lt $start_date);

        my %hash_interval = %hash_curr_workers;
        #FIXME It should be normalised by the length of the time interval
        map {$tot_analysis{$_} += $hash_interval{$_}} keys %hash_interval;

        $max_workers = $num_curr_workers if ($num_curr_workers > $max_workers);

        # We need to repeat the previous value to have an histogram shape
        push @data_timings, [$event_date, $data_timings[-1]->[1]] if @data_timings;
        push @data_timings, [$event_date, \%hash_interval];
    }
    warn $max_workers;
    warn Dumper \%tot_analysis;

    my $total_total = sum(values %tot_analysis);

    my @sorted_analysis_ids = sort {($tot_analysis{$b} <=> $tot_analysis{$a}) || (lc $name{$a} cmp lc $name{$b})} (grep {$tot_analysis{$_}} keys %tot_analysis);
    warn Dumper \@sorted_analysis_ids;
    warn Dumper([map {$name{$_}} @sorted_analysis_ids]);

    if (not $gnuplot_terminal) {
        print join("\t", 'date', 'OVERALL', map {$name{$_}} @sorted_analysis_ids), "\n";
        print join("\t", 'total', $total_total, map {$tot_analysis{$_}} @sorted_analysis_ids), "\n";
        print join("\t", 'proportion', 'NA', map {$tot_analysis{$_}/$total_total} @sorted_analysis_ids), "\n";
        my $s = 0;
        print join("\t", 'cum_proportion', 'NA', map {$s+=$tot_analysis{$_}/$total_total} @sorted_analysis_ids), "\n";

        foreach my $row (@data_timings) {
            print join("\t", $row->[0], sum(values %{$row->[1]}), map {$row->[1]->{$_}} @sorted_analysis_ids)."\n";
        }
        return;
    }

    # Get the number of analysis we want to display
    my $n_relevant_analysis = scalar(@sorted_analysis_ids);
    if ($top and ($top > 0)) {
        if ($top < 1) {
            my $s = 0;
            $n_relevant_analysis = 0;
            map {my $pre_s = $s; $s += $tot_analysis{$_}/$total_total; $pre_s < $top && $n_relevant_analysis++} @sorted_analysis_ids;
        } elsif ($top < scalar(@sorted_analysis_ids)) {
            $n_relevant_analysis = $top;
        }
    }
    # cap based on the length of the palette
    my $need_other_analysis = $n_relevant_analysis < scalar(@sorted_analysis_ids) ? 1 : 0;
    if (($n_relevant_analysis+$need_other_analysis) > scalar(@palette)) {
        $n_relevant_analysis = scalar(@palette) - 1;
        $need_other_analysis = 1;
    }
    $top = $n_relevant_analysis unless $top;
    warn $n_relevant_analysis;

    my @xdata = map {$_->[0]} @data_timings;

    my @datasets = ();

    my $pseudo_zero_value = $logscale ? .8 : -$max_workers / 50;

    # The background plot: the sum of all the analysis
    if ($need_other_analysis) {
        my @ydata = ();
        foreach my $row (@data_timings) {
            push @ydata, sum(map {$row->[1]->{$_}} @sorted_analysis_ids ) || $pseudo_zero_value;
        }
        push @datasets, Chart::Gnuplot::DataSet->new(
            xdata => \@xdata,
            ydata => \@ydata,
            timefmt => '%Y-%m-%dT%H:%M:%S',
            title => 'OTHER',
            style => 'filledcurves x1',
            linewidth => '0',
            color => $palette[$n_relevant_analysis],
        );
    }

    # Each analysis is plotted as the sum of itself and the top ones
    foreach my $i (reverse 1..$n_relevant_analysis) {
        my @ydata;
        foreach my $row (@data_timings) {
            push @ydata, sum(map {$row->[1]->{$_} || 0} @sorted_analysis_ids[0..($i-1)] ) || $pseudo_zero_value;
        }
        my $dataset = Chart::Gnuplot::DataSet->new(
            xdata => \@xdata,
            ydata => \@ydata,
            timefmt => '%Y-%m-%dT%H:%M:%S',
            title => $name{$sorted_analysis_ids[$i-1]},
            style => 'filledcurves x1',
            linewidth => '0',
            color => $palette[$i-1],
        );
        push @datasets, $dataset;
    }

    my $chart = Chart::Gnuplot->new(
        title => sprintf('Profile of %s', $n_relevant_analysis < scalar(@sorted_analysis_ids) ? ($top < 1 ? sprintf('%.1f%% of %s', 100*$top, $url) : "the $top top-analysis of $url") : $url).($start_date ? " from $start_date" : "").($end_date ? " to $end_date" : ""),
        timeaxis => 'x',
        legend => {
            position => 'outside right',
            align => 'left',
        },
        xtics => {
            labelfmt => '%b %d\n %H:00',
        },
        bg => {
            color => 'white',
        },
        imagesize => '1400, 800',
        output => $output,
        terminal => $terminal_mapping{$gnuplot_terminal},
        ylabel => 'Number of workers',
        yrange => [$pseudo_zero_value, undef],
        $logscale ? (logscale => 'y') : (),
    );
    $chart->plot2d(@datasets);

}



__DATA__

=pod

=head1 NAME

    generate_timeline.pl

=head1 DESCRIPTION

    This script is used for offline examination of the allocation of workers.

    Based on the command-line parameters 'start_date' and 'end_date', or on the start time of the first
    worker and end time of the last worker (as recorded in pipeline DB), it pulls the relevant data out
    of the 'worker' table for accurate timing.
    By default, the output is in CSV format, to allow extra analaysis to be carried.

    You can optionally ask the script to generate an image with Gnuplot.


=head1 USAGE EXAMPLES

        # Just run it the usual way: only the top 20 analysis will be reported in CSV format
    generate_timeline.pl -url mysql://username:secret@hostname:port/database > timeline.csv

        # The same, but getting the analysis that fill 99.5% of the global activity in a PNG file
    generate_timeline.pl -url mysql://username:secret@hostname:port/database -top .995 -output timeline.png

        # Assuming you are only interested in a precise interval (in a PNG file)
    generate_timeline.pl -url mysql://username:secret@hostname:port/database -start_date 2013-06-15T10:34 -end_date 2013-06-15T16:58 -output timeline.png

=head1 OPTIONS

    -help                   : print this help
    -url <url string>       : url defining where hive database is located
    -start_date <date>      : minimal start date of a worker (the format is ISO8601, e.g. '2012-01-25T13:46')
    -end_date <date>        : maximal end date of a worker (the format is ISO8601, e.g. '2012-01-25T13:46')
    -top <float>            : maximum number (> 1) or fraction (< 1) of analysis to report (default: 20)
    -output <string>        : output file: its extension must match one of the Gnuplot terminals. Otherwise, the CSV output is produced on stdout

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

