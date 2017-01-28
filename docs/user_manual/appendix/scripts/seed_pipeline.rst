NAME
====

::

        seed_pipeline.pl

SYNOPSIS
========

::

        seed_pipeline.pl {-url <url> | -reg_conf <reg_conf> [-reg_type <reg_type>] -reg_alias <reg_alias>} [ {-analyses_pattern <pattern> | -analysis_id <analysis_id> | -logic_name <logic_name>} [ -input_id <input_id> ] ]

DESCRIPTION
===========

::

        seed_pipeline.pl is a generic script that is used to create {initial or top-up} jobs for hive pipelines

USAGE EXAMPLES
==============

::

            # find out which analyses may need seeding (with an example input_id):

        seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult"


            # seed one job into the "start" analysis:

        seed_pipeline.pl -url "mysql://ensadmin:${ENSADMIN_PSW}@localhost:3306/lg4_long_mult" \
                         -logic_name start -input_id '{"a_multiplier" => 2222222222, "b_multiplier" => 3434343434}'

OPTIONS
=======

Connection parameters
---------------------

::

        -reg_conf <path>            : path to a Registry configuration file
        -reg_type <string>          : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
        -reg_alias <string>         : species/alias name for the Hive DBAdaptor
        -url <url string>           : url defining where hive database is located
        -nosqlvc <0|1>              : skip sql version check if 1

Analysis parameters
-------------------

::

        -analyses_pattern <string>  : seed job(s) for analyses whose logic_name matches the supplied pattern
        -analysis_id <num>          : seed job for analysis with the given analysis_id

Input
-----

::

        -input_id <string>          : specify the input_id as a stringified hash 

Other commands/options
----------------------

::

        -h | -help                  : show this help message

LICENSE
=======

::

        Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
        Copyright [2016] EMBL-European Bioinformatics Institute

        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

             http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License
        is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and limitations under the License.

CONTACT
=======

::

        Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

