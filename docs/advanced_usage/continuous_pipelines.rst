
Continuously running pipelines
==============================

There are two main strategies for running different instances of a workflow
-- i.e. running the same workflow with different starting data. One method,
probably more commonly used, is to instantiate a new eHive database with
:ref:`init_pipeline.pl <script-init_pipeline>` for each new run. Another method is to seed a new Job into
an existing pipeline database. In the second case, the seeded Job will
start a new parallel path through the pipeline.

The latter method can be used to set up an eHive pipeline to provide a
service for on-demand computation. In this arrangement, a single eHive
pipeline is set up, and a Beekeeper is set running continuously. When a Job
is seeded, the Beekeeper will notice the new Job during its next loop, and
will create a Worker to take that Job as appropriate.

Beekeeper options
-----------------

A few :ref:`beekeeper.pl <script-beekeeper>` options should be considered when operating a pipeline in continuous mode:

   - Continuous looping is ensured by setting ``-loop_until FOREVER``

   - It may be desirable to make the pipeline more responsive by reducing the sleep time below one minute using ``-sleep [minutes]``

   - It may be desirable to set the Beekeeper to stop after a certain number of loops using ``-max_loops [number of loops]``

Hoovering the pipeline
----------------------

A continuously running pipeline has the potential to collect thousands of
DONE Job rows in the ``job`` table. As these grow, it has the potential to
slow down the pipeline, as Workers' queries from and updates to the ``job``
table take longer. To rectify this, the :ref:`hoover_pipeline.pl
<script-hoover_pipeline>` script is provided to remove DONE Jobs from the
``job`` table, reducing the size of the table and thereby speeding up
operations involving it.

By default, :ref:`hoover_pipeline.pl <script-hoover_pipeline>` removes DONE
Jobs that finished more than one week ago. The age of DONE Jobs to be
deleted by :ref:`hoover_pipeline.pl <script-hoover_pipeline>` can be
adjusted with the ``-days_ago`` and ``-before_datetime`` options:

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" # removes DONE Jobs that have been DONE for at least one week``

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" -days_ago 1 # removes DONE Jobs that have been DONE for at least one day``

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" -before_datetime "2017-01-01 08:00:00" # removes DONE Jobs that became DONE before 08:00 on January 1st, 2017``


Considerations
--------------

Note that the resource usage statistics are computed for all runs through the pipeline.
