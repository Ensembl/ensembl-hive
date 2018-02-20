.. eHive guide to running pipelines: managing running pipelines

Tools and techniques for managing running pipelines
===================================================

eHive has an internal accounting system to help it efficiently allocate workers
and schedule jobs. In normal operation, the beekeeper updates the status of
eHive components and internal statistics on an intermittent basis, without the
need for intervention from the user. However, in some cases this accounting will
not update correctly - usually when the user circumvents eHive's automated
operation. There are some utility functions available via the beekeeper to
correct these accounting discrepancies.

Synchronizing ("sync"-ing) the pipeline database
------------------------------------------------

There are a number of job counters maintained by the eHive system to
help it manage the worker population, monitor progress, and correctly
block and unblock analyses. These counters are updated periodically, in
a process known as synchronization (or "sync").

The sync process can be computationally expensive in large pipelines, so
syncs are only performed when needed.

Rarely, the job counters will become incorrect during abnormal pipeline
operation, for example if a few process crash, or after jobs are manually
stopped and re-run. In this case, the user may want to manually re-sync the
database. This is done by running beekeeper.pl with the -sync option:

::

            beekeeper.pl -url sqlite:///my_pipeline_database -sync


Re-balancing semaphores
-----------------------

When a group of jobs is organized into a fan and funnel structure, the eHive
system keeps track of how many fan jobs are not :hivestatus:`<DONE>[ DONE ]` or
[ PASSED_ON ]. When that count reaches zero, the semaphore controlling the
funnel job is released. In some abnormal circumstances, for example when workers
are killed without an opportunity to exit cleanly, eHive's internal count of
jobs remaining to do before releasing the semaphore may not represent reality.
Resetting jobs in a fan is another scenario that can cause the semaphore count
to become incorrect. It is possible to force eHive to re-count fan jobs and
update semaphores by running beekeeper.pl with the -balance_semaphores option:

::

           beekeeper.pl -url sqlite:///my_pipeline_database -balance_semaphores

Garbage collection of dead workers
----------------------------------

On occasion, worker processes will end without having an opportunity to update
their status in the hive database. The beekeeper will attempt to find these
workers and update their status itself. It does this by reconciling the list of
worker statuses in the eHive database with information on workers gleaned from
the meadow's process tables (e.g. ``ps``, ``bacct``, ``bjobs``). A manual
reconciliation and update of worker statuses can be invoked by running
beekeeper.pl with the -dead option:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -dead


Tips for performance tuning and load management
-----------------------------------------------


Capacity and batch size
+++++++++++++++++++++++

A number of parameters can help increasing the performance of a pipeline,
but capacities and batch sizes have the most direct effect. Both parameters
go hand in hand.

Although workers run jobs one at a time, they can request (claim) more than
one job (a *batch*) from the database. It means a worker would successively
have:

 * :math:`n` jobs claimed, 0 running, 0 done
 * :math:`n`-1 jobs claimed, 1 running, 0 done
 * :math:`n`-1 jobs claimed, 0 running, 1 done
 * :math:`n`-2 jobs claimed, 1 running, 1 done
 * :math:`n`-2 jobs claimed, 0 running, 2 done
 * etc

It is useful as long as claiming :math:`n` jobs at a time is faster than
claiming :math:`n` times 1 job, and that the claiming process doesn't lock
the table for too long (which would prevent other workers from operating
normally).

This can mitigate the overhead of submitting many small, fast-running jobs
to the farm.  Bear in mind that increasing the batch size helps relieving
the pressure on the job table from claiming jobs *only*. As the job table
is used to track the current status of jobs, it can also be slowed down by
running too many workers, regardless of the batch size. And more generally,
the jobs may create additional load on other databases, filesystems, etc,
which are *your* responsibility to monitor.

Optimizing the batch size is something of an art, as the optimal size is a
function of job runtime and the number of jobs in contention for the hive
database.  Here follows some estimates of the optimal parameters to run a
single analysis, composed of 1 million jobs, under two scenarios:

 * Best *throughput*: the combination of parameters that gets all the jobs
   done the fastest.
 * Best *efficiency*: the combination of parameters that has the highest
   capacity whilst maintaining an overhead per job below 10 milliseconds.
   The overhead is defined as the average amount of time eHive spends per
   job for general housekeeping tasks, but also for claiming. For instance,
   a worker that has lived 660 seconds and run 600 jobs (each set to sleep
   1 second) will have an overhead of 0.1 second per job. eHive has a
   minimum overhead per job of 6-7 milliseconds.

In general, "best throughput" parameters put a lot more pressure on the
database. Only use these parameters if you are in a rush to get your
analysis done, and if you are allowed to use that much resources from the
server (the server might be unable to run someone else's pipeline at the
same time !).

+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+
| Job's duration   | Best efficiency                            | Best throughput                                             |
+                  +----------+-------------+-------------------+----------+------------+-----------------+-------------------+
|                  | Capacity | Batch size  | Analysis duration | Capacity | Batch size | Job overhead    | Analysis duration |
+==================+==========+=============+===================+==========+============+=================+===================+
| 50 ms            | 25       | 20 to 1,000 | 2,315 s           | 100      | 200        | 58 ms (116%)    | 1,080 s           |
+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+
| 100 ms           | 50       | 20 to 1,000 | 2,185 s           | 100      | 200        | 22 ms (22%)     | 1,215 s           |
+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+
| 500 ms           | 100      | 10 to 500   | 5,085 s           | 250      | 100        | 16 ms (3.2%)    | 2,055 s           |
+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+
| 1 s              | 250      | 10 to 50    | 4,040 s           | 500      | 50         | 257 ms (25.7%)  | 2,515 s           |
+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+
| 5 s              | 500      | 20          | 10,020 s          | 2,500    | 20         | 545 ms (10.9%)  | 2,220 s           |
+------------------+----------+-------------+-------------------+----------+------------+-----------------+-------------------+

These values have been determined with a pipeline entirely
made of *Dummy* jobs (they just sleep for a given amount of time) at
various capacities (1, 5, 10, 25, 50, 100, 200 or 250, 500, 1,000, 2,500, 5,000)
and batch sizes (1, 2, 5, 10, 20, 50, 100, 200, 500, 1,000, 2,000, 5,000),
for various sleep times. The notion of sleep models operations on other
databases (data processing with the Ensembl API, for instance), running a
system command, etc.  Although the
actual results are specific to the MySQL server used for the benchmark, the
trend is expected to be the same on other versions of MySQL.


Hive capacity vs analysis capacity
++++++++++++++++++++++++++++++++++

*analysis capacity*

    Limits the number of workers that beekeeper.pl will run for this particular analysis.
    It does not mean if you set it to 200 there will be exactly 200 workers of this analysis,
    as there are other considerations taken into account by the scheduler, but there will be
    no more than 200.

*hive capacity*

    Also limits the number of workers, but globally across the whole pipeline.
    If you set -hive_capacity of an analysis to X it will mean "one Worker of this analysis
    consumes 1/X of the whole Hive's capacity (which equals to 1.0)". Like
    analysis capacity, setting it to 200 means that you will not get more
    than 200 running workers.
    Using it only makes sense if you need several analyses running in
    parallel and consuming the same resource (e.g. accessing the same
    table) to balance load between themselves.

If one of these is set to 0, eHive will not schedule any workers for the
analysis (regardless of the value of the other parameter). If a parameter
is not set (undefined), then its related limiter is unused.

Examples
~~~~~~~~

analysis_capacity=0 and hive_capacity is not set:

  No workers are allowed to run

analysis_capacity=0 and hive_capacity=150:

  No workers are allowed to run

analysis_capacity is not set and hive_capacity=0:

  No workers are allowed to run

analysis_capacity is not set and hive_capacity=150:

  No workers are allowed to run

analysis_capacity=150 and hive_capacity is not set:

  eHive will schedule at most 150 workers for this analysis

A.hive_capacity=1 and B.hive_capacity=300. Examples of allowed numbers of workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 1          | 0          |
  +------------+------------+
  | 0          | 300        |
  +------------+------------+

A.hive_capacity=100, A.analysis_capacity=1 and B.hive_capacity=300. Examples of allowed numbers of workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 1          | 297        |
  +------------+------------+
  | 0          | 300        |
  +------------+------------+

A.hive_capacity=100 and B.hive_capacity=300. Examples of allowed numbers of workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 100        | 0          |
  +------------+------------+
  | 75         | 75         |
  +------------+------------+
  | 50         | 150        |
  +------------+------------+
  | 25         | 225        |
  +------------+------------+
  | 0          | 300        |
  +------------+------------+

A.hive_capacity=100, B.hive_capacity=300 and B.analysis_capacity=210. Examples of allowed numbers of workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 100        | 0          |
  +------------+------------+
  | 75         | 75         |
  +------------+------------+
  | 50         | 150        |
  +------------+------------+
  | 30         | 210        |
  +------------+------------+


More efficient looping
++++++++++++++++++++++

Beekeeper is not constantly active: it works a bit, up to several seconds
depending on the size and complexity of the pipeline, and the
responsiveness of the job scheduler, and then sleeps for a given amount of
time (by default 1 minute, the ``-loop`` parameter).  Every loop, beekeeper
submits ``-submit_workers_max`` workers (which defaults to 50), to avoid
overloading the scheduler with submitted jobs.

You can change both parameters, for instance reduce the loop time to submit
workers more frequently (e.g. 12 seconds == 0.2 minutes), or increase
``-submit_workers_max`` to submit more workers every loop (e.g.  100 or
200) as long as the server supports it.  It is good practice to give
workers time to check-in with the hive database between loops. The default
parameters are safe values that generally work well for production
pipelines, though.

The impact of loop time on the overall time to complete a workflow
will be fairly small, however. When a worker completes a job, it looks
for new jobs that it can run, and will claim and run them automatically
- the beekeeper is not involved in this claiming process. It's only in
the case where new workers need to be created that the workflow would
be waiting for another beekeeper loop.

If you provide the ``-can_respecialize 1`` option to the beekeeper, this
will allow workers to respecialize. That means a worker, in some cases,
can claim and work on jobs of a different analysis when needed. If you
run with ``-can_respecialize 1``, you may notice a significant number of
workers used throughout the pipeline as long as different analyses share
the same resource classes (i.e. the resource classes are not too specific).
For instance, if all the analyses are linked to the same resource-class, a
single worker in ``-can_respecialize 1`` mode would be able to run the
whole pipeline !
Since fewer workers are submitted, the general responsiveness of the
compute cluster and the pipeline are also increased.

Other limiters
++++++++++++++

Besides the analysis-level capacities, the number of running workers is
limited by the ``TotalRunningWorkersMax`` parameter. This parameter has a
default value in the a hive_config.json file in the root of the eHive
directory and can be changed at the beekeeper level with the ``--total_running_workers_max`` option.

Every time the beekeeper loops, it will check the current state of your
eHive workflow and the number of currently running workers. If it
determines more workers are needed, and the ``-total_running_workers_max``
value hasn't been reached, it will submit more, up to the limit of
``-submit_workers_max``.

Database servers
++++++++++++++++

SQLite can have issues when multiple processes are trying to access the
database concurrently because each process acquires locks the whole
database.

MySQL is better at those scenarios and can handle hundreds of concurrent
active connnections. In our experience, the most important parameters of
the server are the amount of RAM available and the size of the `InnoDB
Buffer Pool <https://dev.mysql.com/doc/refman/5.7/en/innodb-buffer-pool.html>`_.

We have only used PostgreSQL in small-scale tests. If you get the chance to
run large pipelines on PostgreSQL, let us know ! We will be interested
in hearing how eHive behaves.

