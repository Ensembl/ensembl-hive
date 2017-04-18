==================
tweak\_pipeline.pl
==================

NAME
----

::

        tweak_pipeline.pl

SYNOPSIS
--------

::

        ./tweak_pipeline.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_file> -reg_alias <reg_alias> ] -tweak 'analysis[mafft%].analysis_capacity=undef'

DESCRIPTION
-----------

::

        This is a script to "tweak" attributes or parameters of an existing Hive pipeline.

OPTIONS
-------

**--url**

::

        url defining where hive database is located

**--reg\_conf**

::

        path to a Registry configuration file

**--reg\_type**

::

        Registry type of the Hive DBAdaptor

**--reg\_alias**

::

        species/alias name for the Hive DBAdaptor

**--nosqlvc**

::

        "No SQL Version Check" - set this to one if you want to force working with a database created by a potentially schema-incompatible API (0 by default)

**--tweak**

::

        An assignment command that performs one individual "tweak". You can "tweak" global/analysis parameters, analysis attributes and resource classes:

            -tweak 'pipeline.param[take_time]=20'                   # override a value of a pipeline-wide parameter; can also create a non-existent parameter
            -tweak 'analysis[take_b_apart].param[base]=10'          # override a value of an analysis-wide parameter; can also create a non-existent parameter
            -tweak 'analysis[add_together].analysis_capacity=undef' # override a value of an analysis attribute
            -tweak 'analysis[add_together].batch_size=15'           # override a value of an analysis_stats attribute
            -tweak 'analysis[part_multiply].resource_class=urgent'  # set the resource class of an analysis (whether a resource class with this name existed or not)
            -tweak 'resource_class[urgent].LSF=-q yesteryear'       # update or create a new resource description

        If multiple "tweaks" are requested, they will be performed in the given order.

**--DELETE**

::

        Shortcut to delete a parameter

**--SHOW**

::

        Shortcut to show a parameter value

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
