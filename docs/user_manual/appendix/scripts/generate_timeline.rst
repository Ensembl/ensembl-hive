NAME
====

generate\_timeline.pl

SYNOPSIS
========

::

        generate_timeline.pl {-url <url> | [-reg_conf <reg_conf>] -reg_alias <reg_alias> [-reg_type <reg_type>] }
                             [-start_date <start_date>] [-end_date <end_date>]
                             [-top <float>]
                             [-mode [workers | memory | cores | pending_workers | pending_time]]
                             [-key [analysis | resource_class]]
                             [-n_core <int>] [-mem <int>]

DESCRIPTION
===========

::

        This script is used for offline examination of the allocation of workers.

        Based on the command-line parameters 'start_date' and 'end_date', or on the start time of the first
        worker and end time of the last worker (as recorded in pipeline DB), it pulls the relevant data out
        of the 'worker' table for accurate timing.
        By default, the output is in CSV format, to allow extra analysis to be carried.

        You can optionally ask the script to generate an image with Gnuplot.

USAGE EXAMPLES
==============

::

            # Just run it the usual way: only the top 20 analysis will be reported in CSV format
        generate_timeline.pl -url mysql://username:secret@hostname:port/database > timeline.csv

            # The same, but getting the analysis that fill 99.5% of the global activity in a PNG file
        generate_timeline.pl -url mysql://username:secret@hostname:port/database -top .995 -output timeline_top995.png

            # Assuming you are only interested in a precise interval (in a PNG file)
        generate_timeline.pl -url mysql://username:secret@hostname:port/database -start_date 2013-06-15T10:34 -end_date 2013-06-15T16:58 -output timeline_June15.png

            # Get the required memory instead of the number of workers
        generate_timeline.pl -url mysql://username:secret@hostname:port/database -mode memory -output timeline_memory.png

OPTIONS
=======

::

        -help                   : print this help
        -url <url string>       : url defining where hive database is located
        -reg_conf               : path to a Registry configuration file 
        -reg_type               : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
        -reg_alias              : species/alias name for the Hive DBAdaptor 
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

EXTERNAL DEPENDENCIES
=====================

::

        Chart::Gnuplot

LICENSE
=======

Copyright [1999-2015] Wellcome Trust Sanger Institute and the
EMBL-European Bioinformatics Institute Copyright [2016] EMBL-European
Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at

::

        http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

CONTACT
=======

Please subscribe to the Hive mailing list:
http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users to discuss
Hive-related questions or to be notified of our updates
