#!/usr/bin/env perl

# Gets the activity of each analysis along time, in a CSV file or in an image (see list of formats supported by GNUplot)

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
use List::Util qw(sum);
use POSIX;
use Data::Dumper;
use Time::Piece;
use Time::Seconds;  # not sure if seconds-only arithmetic also needs it

use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils ('script_usage');

no warnings qw{qw};

main();
exit(0);

sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $help, $verbose, $mode, $start_date, $end_date, $output, $top, $default_memory, $default_cores);

    GetOptions(
                # connect to the database:
            'url=s'                      => \$url,
            'reg_conf|regfile=s'         => \$reg_conf,
            'reg_type=s'                 => \$reg_type,
            'reg_alias|regname=s'        => \$reg_alias,
            'nosqlvc=i'                  => \$nosqlvc,      # using "=i" instead of "!" for consistency with scripts where it is a propagated option

            'verbose!'                   => \$verbose,
            'h|help'                     => \$help,

            'start_date=s'               => \$start_date,
            'end_date=s'                 => \$end_date,
            'mode=s'                     => \$mode,
            'top=f'                      => \$top,
            'mem=i'                      => \$default_memory,
            'n_core=i'                   => \$default_cores,
            'output=s'                   => \$output,
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

    # Check whether $mode is valid
    my %allowed_modes = (
        workers => 'Number of workers',
        memory => 'Memory asked (Gb)',
        cores => 'Number of CPU cores',
        unused_memory => 'Unused memory (Gb)',
        unused_cores => 'Number of unused CPU cores',
        pending_workers => 'Number of pending workers',
    );
    if ($mode) {
        die "Unknown mode '$mode'. Allowed modes are: ".join(", ", keys %allowed_modes) unless exists $allowed_modes{$mode};
        $default_memory = 100 unless $default_memory;
        $default_cores = 1 unless $default_cores;
    } else {
        $mode = 'workers';
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

    # Get the memory usage from each resource_class
    my %mem_resources = ();
    my %cpu_resources = ();
    {
        foreach my $rd (@{$hive_dba->get_ResourceDescriptionAdaptor->fetch_all()}) {
            if ($rd->meadow_type eq 'LSF') {
                $mem_resources{$rd->resource_class_id} = $1 if $rd->submission_cmd_args =~ m/mem=(\d+)/;
                $cpu_resources{$rd->resource_class_id} = $1 if $rd->submission_cmd_args =~ m/-n\s*(\d+)/;
            }
        }
    }
    warn "mem_resources: ", Dumper \%mem_resources if $verbose;
    warn "cpu_resources: ", Dumper \%cpu_resources if $verbose;

    # Get the memory used by each worker
    my %used_res = ();
    if (($mode eq 'unused_memory') or ($mode eq 'unused_cores')) {
        my $sql_used_res = 'SELECT worker_id, mem_megs, cpu_sec/lifespan_sec FROM worker_resource_usage';
        foreach my $db_entry (@{$dbh->selectall_arrayref($sql_used_res)}) {
            my ($worker_id, $mem_megs, $cpu_usage) = @$db_entry;
            $used_res{$worker_id} = [$mem_megs, $cpu_usage];
        }
        warn scalar(keys %used_res), " worker info loaded from worker_resource_usage\n" if $verbose;
    }

    # Get the info about the analysis
    my $analysis_adaptor        = $hive_dba->get_AnalysisAdaptor;
    my %analysis_name           = %{ $analysis_adaptor->fetch_HASHED_FROM_analysis_id_TO_logic_name() };
    my %default_resource_class  = %{ $analysis_adaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id() };
    warn "default_resource_class: ", Dumper \%default_resource_class if $verbose;
    warn "analysis_name: ", Dumper \%analysis_name if $verbose;
    warn scalar(keys %analysis_name), " analysis\n" if $verbose;

    # Get the events from the database
    my %events = ();
    if ($mode ne 'pending_workers') {
        my @tmp_dates = @{$dbh->selectall_arrayref('SELECT when_started, when_finished, born, died, analysis_id, worker_id, resource_class_id FROM worker LEFT JOIN role USING (worker_id)')};
        warn scalar(@tmp_dates), " events\n" if $verbose;

        foreach my $db_entry (@tmp_dates) {
            my ($when_started, $when_finished, $born, $died, $analysis_id, $worker_id, $resource_class_id) = @$db_entry;
            unless($analysis_id) {  # in case there was no Role attached to the Worker - i.e. it has never specialized
                $when_started               = $born;
                $when_finished              = $died;
                $analysis_id                = 0;
                $analysis_name{0}           = 'UNSPECIALIZED';
                $default_resource_class{0}  = 'UNKNOWN';
            }
            $resource_class_id  //= $default_resource_class{$analysis_id};

                # temporary Time::Piece values
            my $birth_datetime = Time::Piece->strptime( $when_started  , '%Y-%m-%d %H:%M:%S');
            my $death_datetime = Time::Piece->strptime( $when_finished , '%Y-%m-%d %H:%M:%S');

                # string values:
            my $birth_date = $birth_datetime->date . 'T' . $birth_datetime->hms;
            my $death_date = $death_datetime->date . 'T' . $death_datetime->hms;

            my $offset = 0;

            if ($mode eq 'workers') {
                $offset = 1;
            } elsif ($mode eq 'memory') {
                $offset = ($mem_resources{$resource_class_id} || $default_memory) / 1024.;
            } elsif ($mode eq 'cores') {
                $offset = ($cpu_resources{$resource_class_id} || $default_cores);
            } elsif ($mode eq 'unused_memory') {
                if (exists $used_res{$worker_id}) {
                    $offset = (($mem_resources{$resource_class_id} || $default_memory) - $used_res{$worker_id}->[0]) / 1024.;
                }
            } else {
                if (exists $used_res{$worker_id}) {
                    $offset = ($cpu_resources{$resource_class_id} || $default_cores) - $used_res{$worker_id}->[1];
                }
            }
            $events{$birth_date}{$analysis_id} += $offset if ($offset > 0);
            $events{$death_date}{$analysis_id} -= $offset if ($offset > 0 and $when_finished);
        }
    } else {
        my @tmp_dates = @{$dbh->selectall_arrayref('SELECT min(when_started), pending_sec, analysis_id FROM role LEFT JOIN worker_resource_usage USING (worker_id) WHERE pending_sec IS NOT NULL AND pending_sec > 0 GROUP BY worker_id')};
        warn scalar(@tmp_dates), " events\n" if $verbose;

        foreach my $db_entry (@tmp_dates) {
            my ($when_started, $pending_sec, $analysis_id) = @$db_entry;

                # temporary Time::Piece values
            my $submitted_datetime = Time::Piece->strptime( $when_started, '%Y-%m-%d %H:%M:%S') - $pending_sec;
            my $started_datetime   = Time::Piece->strptime( $when_started, '%Y-%m-%d %H:%M:%S');

                # string values:
            my $start_pending = $submitted_datetime->date . 'T' . $submitted_datetime->hms;
            my $start_running = $started_datetime->date   . 'T' . $started_datetime->hms;

            $events{$start_pending}{$analysis_id} += 1;
            $events{$start_running}{$analysis_id} -= 1;
        }
    }
    my @event_dates = sort {$a cmp $b} (keys %events);
    warn scalar(@event_dates), " dates\n" if $verbose;

    my $max_workers = 0;
    my @data_timings = ();
    my %tot_analysis = ();

    my $num_curr_workers = 0;
    my %hash_curr_workers = (map {$_ => 0 } (keys %analysis_name));

    foreach my $event_date (@event_dates) {

        last if $end_date and ($event_date gt $end_date);

        my $topup_hash = $events{$event_date};
        foreach my $analysis_id (keys %$topup_hash) {
            $hash_curr_workers{$analysis_id} += $topup_hash->{$analysis_id};
            $num_curr_workers += $topup_hash->{$analysis_id};
        }
        # Due to rounding errors, the sums may be slightly different
        die sum(values %hash_curr_workers)."!=$num_curr_workers" if abs(sum(values %hash_curr_workers) - $num_curr_workers) > 0.05;

        next if $start_date and ($event_date lt $start_date);

        my %hash_interval = %hash_curr_workers;
        #FIXME It should be normalised by the length of the time interval
        map {$tot_analysis{$_} += $hash_interval{$_}} keys %hash_interval;

        $max_workers = $num_curr_workers if ($num_curr_workers > $max_workers);

        # We need to repeat the previous value to have an histogram shape
        push @data_timings, [$event_date, $data_timings[-1]->[1]] if @data_timings;
        push @data_timings, [$event_date, \%hash_interval];
    }
    warn $max_workers if $verbose;
    warn Dumper \%tot_analysis if $verbose;

    my $total_total = sum(values %tot_analysis);

    my @sorted_analysis_ids = sort {($tot_analysis{$b} <=> $tot_analysis{$a}) || (lc $analysis_name{$a} cmp lc $analysis_name{$b})} (grep {$tot_analysis{$_}} keys %tot_analysis);
    warn Dumper \@sorted_analysis_ids if $verbose;
    warn Dumper([map {$analysis_name{$_}} @sorted_analysis_ids]) if $verbose;

    if (not $gnuplot_terminal) {
        print join("\t", 'date', "OVERALL_$mode", map {$analysis_name{$_}} @sorted_analysis_ids), "\n";
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
    warn "$n_relevant_analysis relevant analysis\n" if $verbose;

    my @xdata = map {$_->[0]} @data_timings;

    my @datasets = ();

    my $pseudo_zero_value = -$max_workers / 50;

    # The background plot: the sum of all the analysis
    if ($need_other_analysis) {
        my @ydata = ();
        foreach my $row (@data_timings) {
            push @ydata, sum(map {$row->[1]->{$_}} @sorted_analysis_ids ) || $pseudo_zero_value;
            # Due to rounding errors, values are not always decreased to 0
            $ydata[-1] = $pseudo_zero_value if $ydata[-1] < 0.05;
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
            # Due to rounding errors, values are not always decreased to 0
            $ydata[-1] = $pseudo_zero_value if $ydata[-1] < 0.05;
        }
        my $dataset = Chart::Gnuplot::DataSet->new(
            xdata => \@xdata,
            ydata => \@ydata,
            timefmt => '%Y-%m-%dT%H:%M:%S',
            title => $analysis_name{$sorted_analysis_ids[$i-1]},
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
            labelfmt => '%b %d\n %H:%M',
            along => 'out nomirror',
        },
        bg => {
            color => 'white',
        },
        grid => 'on',
        imagesize => '1400, 800',
        output => $output,
        terminal => $terminal_mapping{$gnuplot_terminal},
        ylabel => $allowed_modes{$mode},
        yrange => [$pseudo_zero_value, undef],
    );
    $chart->plot2d(@datasets);

}



__DATA__

=pod

=head1 NAME

    generate_timeline.pl

=head1 SYNOPSIS

    generate_timeline.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] }
                         [-start_date <start_date>] [-end_date <end_date>]
                         [-top <float>]
                         [-mode [workers | memory | cores | unused_memory | unused_cores | pending_workers]]
                         [-n_core <int>] [-mem <int>]

=head1 DESCRIPTION

    This script is used for offline examination of the allocation of workers.

    Based on the command-line parameters 'start_date' and 'end_date', or on the start time of the first
    worker and end time of the last worker (as recorded in pipeline DB), it pulls the relevant data out
    of the 'worker' table for accurate timing.
    By default, the output is in CSV format, to allow extra analysis to be carried.

    You can optionally ask the script to generate an image with Gnuplot.


=head1 USAGE EXAMPLES

        # Just run it the usual way: only the top 20 analysis will be reported in CSV format
    generate_timeline.pl -url mysql://username:secret@hostname:port/database > timeline.csv

        # The same, but getting the analysis that fill 99.5% of the global activity in a PNG file
    generate_timeline.pl -url mysql://username:secret@hostname:port/database -top .995 -output timeline_top995.png

        # Assuming you are only interested in a precise interval (in a PNG file)
    generate_timeline.pl -url mysql://username:secret@hostname:port/database -start_date 2013-06-15T10:34 -end_date 2013-06-15T16:58 -output timeline_June15.png

        # Get the required memory instead of the number of workers
    generate_timeline.pl -url mysql://username:secret@hostname:port/database -mode memory -output timeline_memory.png


=head1 OPTIONS

    -help                   : print this help
    -url <url string>       : url defining where hive database is located
    -reg_cong, -reg_type, -reg_alias    : alternative connection details
    -nosqlvc                : Do not restrict the usage of this script to the current version of eHive
                              Be aware that generate_timeline.pl uses raw SQL queries that may break on different schema versions
    -verbose                : Print some info about the data loaded from the database

    -start_date <date>      : minimal start date of a worker (the format is ISO8601, e.g. '2012-01-25T13:46')
    -end_date <date>        : maximal end date of a worker (the format is ISO8601, e.g. '2012-01-25T13:46')
    -top <float>            : maximum number (> 1) or fraction (< 1) of analysis to report (default: 20)
    -output <string>        : output file: its extension must match one of the Gnuplot terminals. Otherwise, the CSV output is produced on stdout
    -mode <string>          : what should be displayed on the y-axis. Allowed values are 'workers' (default), 'memory', 'cores', 'unused_memory', 'unused_cores', 'pending_workers'

    -n_core <int>           : the default number of cores allocated to a worker (default: 1)
    -mem <int>              : the default memory allocated to a worker (default: 100Mb)

=head1 EXTERNAL DEPENDENCIES

    Chart::Gnuplot

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

