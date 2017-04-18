==================
generate\_graph.pl
==================

NAME
----

::

        generate_graph.pl

SYNOPSIS
--------

::

        ./generate_graph.pl -help

        ./generate_graph.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_file> -reg_alias <reg_alias> ] [-pipeconfig TopUp_conf.pm]* -output OUTPUT_LOC

DESCRIPTION
-----------

::

        This program will generate a graphical representation of your hive pipeline.
        This includes visualising the flow of data from the different analyses, blocking
        rules & table writers. The graph is also coloured to indicate the stage
        an analysis is at. The colours & fonts used can be configured via
        hive_config.json configuration file.

OPTIONS
-------

**--url**

::

        url defining where hive database is located

**--reg\_conf**

::

        path to a Registry configuration file

**--reg\_alias**

::

        species/alias name for the Hive DBAdaptor

**--nosqlvc**

::

        if 1, don't check sql schema version

**--config\_file**

::

        Path to JSON hive config file

**--pipeconfig**

::

        A pipeline configuration file that can function both as the initial source of pipeline structure or as a top-up config.
        This option can now be used multiple times for multiple top-ups.

**--format**

::

        (Optional) specify the output format, or override the output format specified by the output file's extension
        (e.g. png, jpeg, dot, gif, ps)

**--output**

::

        Location of the file to write to.
        The file extension (.png , .jpeg , .dot , .gif , .ps) will define the output format.

**--help**

::

        Print this help message

EXTERNAL DEPENDENCIES
---------------------

::

        GraphViz

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
