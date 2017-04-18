===================
hoover\_pipeline.pl
===================

NAME
----

::

        hoover_pipeline.pl

SYNOPSIS
--------

::

        hoover_pipeline.pl {-url <url> | -reg_conf <reg_conf> -reg_alias <reg_alias>} [ { -before_datetime <datetime> | -days_ago <days_ago> } ]

DESCRIPTION
-----------

::

        hoover_pipeline.pl is a script used to remove old 'DONE' jobs from a continuously running pipeline database

USAGE EXAMPLES
--------------

::

            # delete all jobs that have been 'DONE' for at least a week (default threshold) :

        hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"


            # delete all jobs that have been 'DONE' for at least a given number of days

        hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -days_ago 3


            # delete all jobs 'DONE' before a specific datetime:

        hoover_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" -before_datetime "2013-02-14 15:42:50"

OPTIONS
-------

::

        -reg_conf <path>          : path to a Registry configuration file
        -reg_type <string>        : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
        -reg_alias <string>       : species/alias name for the Hive DBAdaptor
        -url <url string>         : url defining where hive database is located
        -nosqlvc <0|1>            : skip sql version check if 1
        -before_datetime <string> : delete jobs 'DONE' before a specific time
        -days_ago <num>           : delete jobs that have been 'DONE' for at least <num> days
        -h | -help                : show this help message

LICENSE
-------

::

        Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
        Copyright [2016-2017] EMBL-European Bioinformatics Institute

        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

             http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License
        is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and limitations under the License.

CONTACT
-------

::

        Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates
