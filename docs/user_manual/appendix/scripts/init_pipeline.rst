=================
init\_pipeline.pl
=================

NAME
----

::

        init_pipeline.pl

SYNOPSIS
--------

::

        init_pipeline.pl <config_module_or_filename> [<options_for_this_particular_pipeline>]

DESCRIPTION
-----------

::

        init_pipeline.pl is a generic script that is used to create+setup=initialize eHive pipelines from PipeConfig configuration modules.

USAGE EXAMPLES
--------------

::

            # get this help message:
        init_pipeline.pl

            # initialize a generic eHive pipeline:
        init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf -password <yourpassword>

            # initialize the long multiplicaton pipeline by supplying not only mandatory but also optional data:
            #   (assuming your current directory is ensembl-hive/modules/Bio/EnsEMBL/Hive/PipeConfig) :
        init_pipeline.pl LongMult_conf -password <yourpassword> -first_mult 375857335 -second_mult 1111333355556666 

OPTIONS
-------

::

        -hive_force_init <0|1> :  If set to 1, forces the (re)creation of the hive database even if a previous version of it is present in the server.
        -tweak <string>        :  Apply tweaks to the pipeline. See tweak_pipeline.pl for details of tweaking syntax
        -DELETE                :  Delete pipeline parameter (shortcut for tweak DELETE)
        -SHOW                  :  Show  pipeline parameter  (shortcut for tweak SHOW)
        -h | --help            :  Show this help message

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
