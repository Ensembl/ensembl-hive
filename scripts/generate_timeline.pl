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

# This replaces "when_died" when a role is still active
my $now = localtime;

main();
exit(0);

sub main {

    my ($url, $reg_conf, $reg_type, $reg_alias, $nosqlvc, $help, $verbose, $mode, $start_date, $end_date, $output, $top, $default_memory, $default_cores, $key);

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
            'key=s'                      => \$key,
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
        memory => 'Memory asked / unused (Gb)',
        cores => 'Number of CPU cores asked / unused',
        pending_workers => 'Number of pending workers',
        pending_time => 'Average instantaneous pending time (min.)',
    );
    if ($mode) {
        die "Unknown mode '$mode'. Allowed modes are: ".join(", ", keys %allowed_modes) unless exists $allowed_modes{$mode};
        $default_memory = 100 unless $default_memory;
        $default_cores = 1 unless $default_cores;
    } else {
        $mode = 'workers';
    }

    my %allowed_keys = (
        analysis => 'Analysis',
        resource_class => 'Resource class',
    );
    if ($key) {
        die "Unknown key '$key'. Allowed keys are: ".join(", ", keys %allowed_keys) unless exists $allowed_keys{$key};
    } else {
        $key = 'analysis';
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

    my $additive_layer = (($mode eq 'memory') or ($mode eq 'cores')) ? 1 : 0;

    # Get the resource usage information of each worker
    my %used_res = ();
    if (($mode eq 'memory') or ($mode eq 'cores') or ($mode eq 'pending_workers') or ($mode eq 'pending_time')) {
        my $sql_used_res = 'SELECT worker_id, mem_megs, cpu_sec/lifespan_sec, pending_sec FROM worker_resource_usage';
        foreach my $db_entry (@{$dbh->selectall_arrayref($sql_used_res)}) {
            my $worker_id = shift @$db_entry;
            $used_res{$worker_id} = $db_entry;
        }
        warn scalar(keys %used_res), " worker info loaded from worker_resource_usage\n" if $verbose;
    }

    # Get the info about the analysis
    my $analysis_adaptor        = $hive_dba->get_AnalysisAdaptor;
    my %default_resource_class  = %{ $analysis_adaptor->fetch_HASHED_FROM_analysis_id_TO_resource_class_id() };
    my $rc_adaptor              = $hive_dba->get_ResourceClassAdaptor;
    warn "default_resource_class: ", Dumper \%default_resource_class if $verbose;
    my %key_name = %{$key eq 'analysis'
        ? $analysis_adaptor->fetch_HASHED_FROM_analysis_id_TO_logic_name()
        : $rc_adaptor->fetch_HASHED_FROM_resource_class_id_TO_name()
    };
    $key_name{-1} = 'UNSPECIALIZED';
    warn scalar(keys %key_name), " keys: ", Dumper \%key_name if $verbose;

    # Get the events from the database
    my %events = ();
    my %layers = ();
    {
        my $sql = $key eq 'analysis'
            ? 'SELECT when_born, when_died, worker_id, resource_class_id, analysis_id FROM worker LEFT JOIN role USING (worker_id)'
            : 'SELECT when_born, when_died, worker_id, resource_class_id FROM worker';
        my @tmp_dates = @{$dbh->selectall_arrayref($sql)};
        warn scalar(@tmp_dates), " rows\n" if $verbose;

        foreach my $db_entry (@tmp_dates) {
            my ($when_born, $when_died, $worker_id, $resource_class_id, $analysis_id) = @$db_entry;

            # In case $resource_class_id is undef
            next unless $resource_class_id or $analysis_id;
            $resource_class_id  //= $default_resource_class{$analysis_id};
            my $key_value = $key eq 'analysis' ? $analysis_id : $resource_class_id;
            $key_value = -1 if not defined $key_value;

            if ($mode eq 'workers') {
                add_event(\%events, $key_value, $when_born, $when_died, 1);

            } elsif ($mode eq 'memory') {
                my $offset = ($mem_resources{$resource_class_id} || $default_memory) / 1024.;
                add_event(\%events, $key_value, $when_born, $when_died, $offset);
                $offset = ($used_res{$worker_id}->[0]) / 1024. if exists $used_res{$worker_id} and $used_res{$worker_id}->[0];
                add_event(\%layers, $key_value, $when_born, $when_died, $offset);

            } elsif ($mode eq 'cores') {
                my $offset = ($cpu_resources{$resource_class_id} || $default_cores);
                add_event(\%events, $key_value, $when_born, $when_died, $offset);
                $offset = $used_res{$worker_id}->[1] if exists $used_res{$worker_id} and $used_res{$worker_id}->[1];
                add_event(\%layers, $key_value, $when_born, $when_died, $offset);
            } else {
                if (exists $used_res{$worker_id} and $used_res{$worker_id}->[2]) {
                    my $pending_sec = $used_res{$worker_id}->[2];
                    add_event(\%events, $key_value, -$pending_sec, $when_born, 1);
                    add_event(\%layers, $key_value, -$pending_sec, $when_born, $pending_sec/60);
                }
            }
        }
    }
    warn "Events recorded: ", scalar(keys %events), " ", scalar(keys %layers), "\n" if $verbose;

    my @event_dates = sort {$a cmp $b} (keys %events);

    my $time_samples_data = cumulate_events(\%events, [keys %key_name], $start_date, $end_date, \%events, $verbose);
    my %tot_analysis = %{$time_samples_data->[0]};
    my @xdata        = map {$_->[0]} @{$time_samples_data->[1]};
    my @data_timings = map {$_->[1]} @{$time_samples_data->[1]};
    my $max_workers  =   $time_samples_data->[2];

    my $total_total = sum(values %tot_analysis);

    my @sorted_key_ids = sort {($tot_analysis{$b} <=> $tot_analysis{$a}) || (lc $key_name{$a} cmp lc $key_name{$b})} (grep {$tot_analysis{$_}} keys %tot_analysis);
    warn "Sorted key_ids: ", Dumper \@sorted_key_ids if $verbose;
    warn Dumper([map {$key_name{$_}} @sorted_key_ids]) if $verbose;

    if (not $gnuplot_terminal) {
        print join("\t", 'date', "OVERALL_$mode", map {$key_name{$_}} @sorted_key_ids), "\n";
        print join("\t", 'total', $total_total, map {$tot_analysis{$_}} @sorted_key_ids), "\n";
        print join("\t", 'proportion', 'NA', map {$tot_analysis{$_}/$total_total} @sorted_key_ids), "\n";
        my $s = 0;
        print join("\t", 'cum_proportion', 'NA', map {$s+=$tot_analysis{$_}/$total_total} @sorted_key_ids), "\n";

        foreach my $row (@{$time_samples_data->[1]}) {
            print join("\t", $row->[0], sum(values %{$row->[1]}), map {$row->[1]->{$_}} @sorted_key_ids)."\n";
        }
        return;
    }

    my $layer_samples_data = cumulate_events(\%layers, [keys %key_name], $start_date, $end_date, \%events, $verbose);
    my @layer_timings = map {$_->[1]} @{$layer_samples_data->[1]};

    if ($mode eq 'pending_time') {
        foreach my $j (1..(scalar(@data_timings))) {
            foreach my $i (@sorted_key_ids) {
                next if $data_timings[$j-1]->{$i} == 0;
                $data_timings[$j-1]->{$i} = $layer_timings[$j-1]->{$i} / $data_timings[$j-1]->{$i};
            }
        }
    }

    my ($n_relevant_analysis, $need_other_analysis, $real_top) = count_number_relevant_sets(\@sorted_key_ids, \%tot_analysis, $total_total, $top, scalar(@palette), $verbose);

    my @datasets = ();

    my $pseudo_zero_value = -$max_workers / 50;

    # The background plot: the sum of all the analysis
    if ($need_other_analysis) {
        add_dataset(\@datasets, \@data_timings, \@layer_timings, \@xdata,
            \@sorted_key_ids, 'OTHER', $palette[$n_relevant_analysis], $pseudo_zero_value, $additive_layer ? [@sorted_key_ids[$n_relevant_analysis..(scalar(@sorted_key_ids)-1)]] : undef);
    }

    # Each analysis is plotted as the sum of itself and the top ones
    foreach my $i (reverse 1..$n_relevant_analysis) {
        add_dataset(\@datasets, \@data_timings, \@layer_timings, \@xdata,
            [@sorted_key_ids[0..($i-1)]], $key_name{$sorted_key_ids[$i-1]}, $palette[$i-1], $pseudo_zero_value, $additive_layer ? [$sorted_key_ids[$i-1]] : undef);
    }

    # The main Gnuplot object
    my $chart = Chart::Gnuplot->new(
        title => sprintf('Profile of %s%s', $n_relevant_analysis < scalar(@sorted_key_ids) ? sprintf('the %s top-analysis of ', $real_top ? ($real_top < 1 ? sprintf('%.1f%%', 100*$real_top) : $real_top) : $n_relevant_analysis) : '', $url)
                 .($start_date ? " from $start_date" : "").($end_date ? " to $end_date" : ""),
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


#####
# Function to add a new Gnuplot dataset
# It needs a list of key IDs to represent (i.e. to sum) and optionally some
# key IDs to substract (represented as hashed)
#####

sub add_dataset {
    my ($datasets, $data_timings, $layer_timings, $xdata, $key_ids_to_sum, $title, $color, $pseudo_zero_value, $analysis_ids_pattern) = @_;

    my @ydata;
    foreach my $row (@$data_timings) {
        my $y = sum(map {$row->{$_} || 0} @$key_ids_to_sum) || $pseudo_zero_value;
        # Due to rounding errors, values are not always decreased to 0
        push @ydata, $y < 0.05 ? $pseudo_zero_value : $y;
    }
    my $dataset = Chart::Gnuplot::DataSet->new(
        xdata => $xdata,
        ydata => \@ydata,
        timefmt => '%Y-%m-%dT%H:%M:%S',
        style => 'filledcurves x1',
        linewidth => '0',
        color => $color,
    );
    push @$datasets, $dataset;

    if (defined $analysis_ids_pattern) {
        $dataset->{fill} = {pattern => 1};
        my @ydatal = @ydata;
        foreach my $j (1..(scalar(@$data_timings))) {
            my $y = $ydata[$j-1];
            next if $y == $pseudo_zero_value;
            my $dt = $data_timings->[$j-1];
            my $lt = $layer_timings->[$j-1];
            foreach my $i (@$analysis_ids_pattern) {
                $y += ($lt->{$i} || 0) - ($dt->{$i} || 0);
            }
            $ydatal[$j-1] = $y < 0.05 ? $pseudo_zero_value : $y;
        }
        $dataset = Chart::Gnuplot::DataSet->new(
            xdata => $xdata,
            ydata => \@ydatal,
            timefmt => '%Y-%m-%dT%H:%M:%S',
            style => 'filledcurves x1',
            linewidth => '0',
            color => $color,
        );
        push @$datasets, $dataset;
    }
    $dataset->{title} = $title;
}


#####
# Function to store add a new event to the hash.
# Events are defined with birth and death dates (the birth can be defined
# relatively to the death)
# NB: The dates are truncated to the minute: seconds are not recorded
# NB: Does not add anything if birth and death are identical (after
# truncation)
#####

sub add_event {
    my ($events, $key, $when_born, $when_died, $offset) = @_;

    return if $offset <= 0;

        # temporary Time::Piece values
    my $death_datetime = $when_died ? Time::Piece->strptime( $when_died , '%Y-%m-%d %H:%M:%S') : $now;
    my $birth_datetime = ($when_born =~ /^-[0-9]/) ? $death_datetime + $when_born : Time::Piece->strptime( $when_born , '%Y-%m-%d %H:%M:%S');

    # We don't need to draw things at the resolution of 1 second; 1 minute is enough
    $death_datetime->[0] = 0;
    $birth_datetime->[0] = 0;

        # string values:
    my $birth_date = $birth_datetime->date . 'T' . $birth_datetime->hms;
    my $death_date = $death_datetime->date . 'T' . $death_datetime->hms;
    return if $birth_date eq $death_date;

    $events->{$birth_date}{$key} += $offset;
    $events->{$death_date}{$key} -= $offset;
}


#####
# Cumulate all the events between start_date and end_date
# A reference list of events can be passed to handle the layered
# information
#####

sub cumulate_events {
    my ($events, $key_names, $start_date, $end_date, $ref_events, $verbose) = @_;

    my @event_dates = sort {$a cmp $b} (keys %$ref_events);
    warn scalar(@event_dates), " dates\n" if $verbose;

    my $max_workers = 0;
    my @data_timings = ();
    my %tot_area = ();

    my $num_curr_workers = 0;
    my %hash_curr_workers = (map {$_ => 0 } @$key_names);

    foreach my $event_date (@event_dates) {

        last if $end_date and ($event_date gt $end_date);
        next unless exists $events->{$event_date};

        my $topup_hash = $events->{$event_date};
        foreach my $key_id (keys %$topup_hash) {
            $hash_curr_workers{$key_id} += $topup_hash->{$key_id};
            $num_curr_workers += $topup_hash->{$key_id};
        }
        # Due to rounding errors, the sums may be slightly different
        die sum(values %hash_curr_workers)."!=$num_curr_workers" if abs(sum(values %hash_curr_workers) - $num_curr_workers) > 0.05;

        next if $start_date and ($event_date lt $start_date);

        my %hash_interval = %hash_curr_workers;
        #FIXME It should be normalised by the length of the time interval
        map {$tot_area{$_} += $hash_interval{$_}} keys %hash_interval;

        $max_workers = $num_curr_workers if ($num_curr_workers > $max_workers);

        # We need to repeat the previous value to have an histogram shape
        push @data_timings, [$event_date, { %{$data_timings[-1]->[1]} }] if @data_timings;
        push @data_timings, [$event_date, \%hash_interval];
    }
    push @data_timings, [$end_date, { %{$data_timings[-1]->[1]} }] if @data_timings and $end_date and ($data_timings[-1]->[0] lt $end_date);
    warn "Last timing: ", Dumper $data_timings[-1] if $verbose and @data_timings;
    warn "Highest y value: ", $max_workers, "\n" if $verbose;
    warn "Total area: ", Dumper \%tot_area if $verbose;

    return [\%tot_area, \@data_timings, $max_workers];
}



#####
# Function to translate $top (which can be an integer or a float between 0
# and 1) to the number of keys that should be displayed in the legend.
# This is done in accordance to the numbers of available colors in the
# palette, and the relative importance of each category (the most present
# ones are selected first)
#####

sub count_number_relevant_sets {
    my ($sorted_key_ids, $tot_analysis, $total_total, $top, $n_colors_in_palette, $verbose) = @_;

    # Get the number of analysis we want to display
    my $n_relevant_analysis = scalar(@$sorted_key_ids);
    if ($top and ($top > 0)) {
        if ($top < 1) {
            my $s = 0;
            $n_relevant_analysis = 0;
            map {my $pre_s = $s; $s += $tot_analysis->{$_}/$total_total; $pre_s < $top && $n_relevant_analysis++} @$sorted_key_ids;
        } elsif ($top < scalar(@$sorted_key_ids)) {
            $n_relevant_analysis = $top;
        }
    }
    # cap based on the length of the palette
    my $need_other_analysis = $n_relevant_analysis < scalar(@$sorted_key_ids) ? 1 : 0;
    if (($n_relevant_analysis+$need_other_analysis) > $n_colors_in_palette) {
        $n_relevant_analysis = $n_colors_in_palette - 1;
        $need_other_analysis = 1;
    }

    warn "$n_relevant_analysis relevant analysis\n" if $verbose;
    return ($n_relevant_analysis, $need_other_analysis, $top);
}

__DATA__

=pod

=head1 NAME

generate_timeline.pl

=head1 SYNOPSIS

    generate_timeline.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] }
                         [-start_date <start_date>] [-end_date <end_date>]
                         [-top <float>]
                         [-mode [workers | memory | cores | pending_workers | pending_time]]
                         [-key [analysis | resource_class]]
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
    -mode <string>          : what should be displayed on the y-axis. Allowed values are 'workers' (default), 'memory', 'cores', 'pending_workers', or 'pending_time'
    -key                    : 'analysis' (default) or 'resource_class': how to bin the workers

    -n_core <int>           : the default number of cores allocated to a worker (default: 1)
    -mem <int>              : the default memory allocated to a worker (default: 100Mb)

=head1 EXTERNAL DEPENDENCIES

    Chart::Gnuplot

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

