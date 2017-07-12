==============================
Continuously running pipelines
==============================

There are two main strategies for running different instances of an analysis within the same workflow -- i.e. running the same workflow with different starting data. One method, probably more commonly used, is to instantiate a new hive database with init_pipeline.pl for each new analysis run. Another method is to seed a new job into an existing pipeline (into an already existing hive database). In the second case, the seeded job will start a new parallel path through the pipeline.

The latter method can be used to set up an eHive pipeline to provide a service for on-demand computation. In this arrangement, a single hive pipeline is set up, and a beekeeper is set running continuously. When a job is seeded, the beekeeper will notice the new job during its next loop, and will create workers to take that job as appropriate.

Beekeeper options
-----------------

A few beekeeper.pl options should be considered when operating a pipeline in continuous mode:

   - Continuous looping is ensured by setting ``-loop_until FOREVER``

   - It may be desirable to make the pipeline more responsive by reducing the sleep time below one minute using ``-sleep [minutes]``

   - It may be desirable to set the beekeeper to stop after a certain number of loops using ``-max_loops [number of loops]``

Hoovering the pipeline
----------------------

A continuously running pipeline has the potential to collect thousands of DONE job rows in the jobs table. As these grow, it has the potential to slow down the pipeline, as worker's queries from and updates to the job table take longer. To rectify this, the hoover_pipeline.pl script is provided to remove DONE jobs from the job table, reducing the size of the table and thereby speeding up operations involving it.

By default, hoover_pipeline.pl removes DONE jobs that finished more than one week ago. The age of DONE jobs to be deleted by hoover_pipeline.pl can be adjusted with the -days_ago and -before_datetime options:

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" # removes DONE jobs that have been DONE for at least one week``

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" -days_ago 1 # removes DONE jobs that have been DONE for at least one day``

   - ``hoover_pipeline.pl -url "sqlite:///my_hive_db" -before_datetime "2017-01-01 08:00:00" # removes DONE jobs that became DONE before 08:00 on January 1st, 2017``


Considerations
--------------

Note that the resource usage statistics are computed for all runs through the pipeline.
