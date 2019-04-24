.. _tweak-pipeline-script:

Changing and viewing pipeline configuration
+++++++++++++++++++++++++++++++++++++++++++

eHive provides a tool to modify many aspects of a pipeline after it has been loaded into an eHive database. This is the ``tweak_pipeline.pl`` script. Using this script, you can change the values of Analysis or pipeline-wide parameters. This script can also change Resource Classes for Analyses, and it can even be used to alter the dataflow structure of a pipeline.

Basic operation
===============

Typically, ``tweak_pipeline.pl`` is invoked with two sets of parameters: the eHive database (passed as a url (``-url``) or as part of a registry configuration (``-reg_conf``)), and a statement written in the tweak language (for details, see the :ref:`tweak-language-reference`). The tweak language is designed to be intuitive, consisting of a verb (``-SET``, ``-SHOW``, ``-DELETE``, or ``-tweak``) followed by the name of the attribute and the attribute's new value (if appropriate). Some examples:

Setting or changing attributes
------------------------------

    - Set or change the value of a pipeline-wide parameter:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET 'pipeline.param[take_time]=20'``

    - Set or change the value of a hive meta-attribute:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET 'pipeline.hive_pipeline_name=new_name'``

    - Set or change the resource class for a group of Analyses, using pattern matching to match multiple Analysis names:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET 'analysis[blast%].resource_class=himem'``

    - Set or change dataflow for an analysis:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET 'analysis[some_analysis].flow_into={1=>"another_analysis"}'``

Viewing attributes
------------------

    - View a pipeline meta-attribute:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SHOW 'pipeline.hive_pipeline_name'``

    - View the description for a resource class:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SHOW 'resource_class[urgent].LSF'``

Deleting attributes
-------------------

    - Delete an analysis-wide parameter:

``tweak_pipeline.pl -url sqlite:///my_hive_db -DELETE 'analysis[add_together].param[bar]'``

Remember that ``tweak_pipeline.pl`` only affects values in the hive database. In order to make tweaks permanent, the changes need to also be made in the corresponding PipeConfig file.

.. _tweak-language-reference:

Tweak language reference
========================

The ``tweak_pipeline.pl`` script uses a flexible language to specify which pipeline attributes to set, change, or show. Each tweak consists of a verb, followed by a description of the attribute. Finally, the new value for that attribute is given if required.

Verbs
-----

The verb can be one of four values:

    - ``-SET``: changes the current value for the given attribute.

    - ``-SHOW``: returns the current value for the given attribute.

    - ``-DELETE``: deletes any value for the given attribute.

    - ``-tweak``: generic invocation of a tweak.

        - If ``-tweak`` is followed by an attribute name and a ``?``, then the current value of that attribute is returned - similar to ``-SHOW``. Example:

``tweak_pipeline.pl -url sqlite:///my_hive_db -tweak 'pipeline.hive_pipeline_name?'``

        - If an attribute name is provided, along with a new value separated by ``=``, then the attribute's value is updated to the new value. This is the same as ``-SET``. Example:

``tweak_pipeline.pl -url sqlite:///my_hive_db -tweak 'pipeline.param[take_time]=20'``

        - If tweak is followed by an attribute name and a ``#``, then the attribute is deleted. This is the same as ``-DELETE``. Example:

``tweak_pipeline.pl -url sqlite:///my_hive_db -tweak 'pipeline.param[take_time]#'``

Attribute description
---------------------

The attribute being tweaked is identified using a two-part name, with the two parts separated by a dot.

    - The first part identifies the "domain" of the attribute. This can be one of:

        - ``pipeline``

        - ``analysis``

        - ``resource_class``

    - In the case of ``analysis`` or ``resource_class``, the particular Analysis or Resource Class is identified by placing the logic name in brackets like this:

``analysis[logic_name]`` e.g. ``analysis[dump_sequence]``

    - The second part identifies the particular attribute within that domain to view, modify, or delete. Allowable values for this part depend on the domain:

+----------------+--------------------------------+-----------------------------------------+
| Domain         |       Possible attributes      | Notes                                   |
+================+================================+=========================================+
| pipeline       | hive_auto_rebalance_semaphores |                                         |
+                +--------------------------------+-----------------------------------------+
|                | hive_pipeline_name             |                                         |
+                +--------------------------------+-----------------------------------------+
|                | hive_sql_schema_version        | display only                            |
+                +--------------------------------+-----------------------------------------+
|                | hive_use_param_stack           |                                         |
+                +--------------------------------+-----------------------------------------+
|                | param                          | Requires a parameter name in [brackets] |
+----------------+--------------------------------+-----------------------------------------+
| analysis       | analysis_capacity              |                                         |
+                +--------------------------------+-----------------------------------------+
|                | batch_size                     |                                         |
+                +--------------------------------+-----------------------------------------+
|                | can_be_empty                   |                                         |
+                +--------------------------------+-----------------------------------------+
|                | comment                        |                                         |
+                +--------------------------------+-----------------------------------------+
|                | dbID                           | display only                            |
+                +--------------------------------+-----------------------------------------+
|                | failed_job_tolerance           |                                         |
+                +--------------------------------+-----------------------------------------+
|                | flow_into                      |                                         |
+                +--------------------------------+-----------------------------------------+
|                | hive_capacity                  |                                         |
+                +--------------------------------+-----------------------------------------+
|                | max_retry_count                |                                         |
+                +--------------------------------+-----------------------------------------+
|                | meadow_type                    |                                         |
+                +--------------------------------+-----------------------------------------+
|                | param                          | requires a parameter name in [brackets] |
+                +--------------------------------+-----------------------------------------+
|                | priority                       |                                         |
+                +--------------------------------+-----------------------------------------+
|                | resource_class                 |                                         |
+                +--------------------------------+-----------------------------------------+
|                | tags                           |                                         |
+                +--------------------------------+-----------------------------------------+
|                | wait_for                       |                                         |
+----------------+--------------------------------+-----------------------------------------+
| resource_class | meadow name (e.g. LSF)         |                                         |
+----------------+--------------------------------+-----------------------------------------+


