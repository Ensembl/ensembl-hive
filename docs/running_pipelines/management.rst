.. eHive guide to running pipelines: managing running pipelines

Tools and techniques for managing running pipelines
===================================================

eHive has an internal accounting system to help it efficiently allocate Workers
and schedule Jobs. In normal operation, the Beekeeper updates the status of
eHive components and internal statistics on an intermittent basis, without the
need for intervention from the user. However, in some cases this accounting will
not update correctly - usually when the user circumvents eHive's automated
operation. There are some utility functions available via the Beekeeper to
correct these accounting discrepancies.

Synchronizing ("sync"-ing) the pipeline database
------------------------------------------------

There are a number of Job counters maintained by the eHive system to
help it manage the Worker population, monitor progress, and correctly
block and unblock Analyses. These counters are updated periodically, in
a process known as synchronization (or "sync").

The sync process can be computationally expensive in large pipelines, so
syncs are only performed when needed.

Rarely, the Job counters will become incorrect during abnormal pipeline
operation, for example if a few process crash, or after Jobs are manually
stopped and re-run. In this case, the user may want to manually re-sync the
database. This is done by running ``beekeeper.pl`` with the -sync option:

::

            beekeeper.pl -url sqlite:///my_pipeline_database -sync


Re-balancing semaphores
-----------------------

When a group of Jobs is organized into a fan and funnel structure, the eHive
system keeps track of how many fan Jobs are not :hivestatus:`<DONE>[ DONE ]` or
[ PASSED_ON ]. When that count reaches zero, the semaphore controlling the
funnel Job is released. In some abnormal circumstances, for example when Workers
are killed without an opportunity to exit cleanly, eHive's internal count of
Jobs remaining to do before releasing the semaphore may not represent reality.
Resetting Jobs in a fan is another scenario that can cause the semaphore count
to become incorrect. It is possible to force eHive to re-count fan Jobs and
update semaphores by running ``beekeeper.pl`` with the -balance_semaphores option:

::

           beekeeper.pl -url sqlite:///my_pipeline_database -balance_semaphores

Garbage collection of dead Workers
----------------------------------

On occasion, Worker processes will end without having an opportunity to update
their status in the eHive database. The Beekeeper will attempt to find these
Workers and update their status itself. It does this by reconciling the list of
Worker statuses in the eHive database with information on Workers gleaned from
the meadow's process tables (e.g. ``ps``, ``bacct``, ``bjobs``). A manual
reconciliation and update of Worker statuses can be invoked by running
``beekeeper.pl`` with the -dead option:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -dead


Tips for performance tuning and load management
-----------------------------------------------

.. _capacity-and-batch-size:

Capacity and batch size
+++++++++++++++++++++++

A number of parameters can help increasing the performance of a pipeline,
but capacities and batch sizes have the most direct effect. Both parameters
go hand in hand.

Although Workers run Jobs one at a time, they can request (claim) more than
one Job (a *batch*) from the database. It means a Worker would successively
have:

 * :math:`n` Jobs claimed, 0 running, 0 done
 * :math:`n`-1 Jobs claimed, 1 running, 0 done
 * :math:`n`-1 Jobs claimed, 0 running, 1 done
 * :math:`n`-2 Jobs claimed, 1 running, 1 done
 * :math:`n`-2 Jobs claimed, 0 running, 2 done
 * etc.

It is useful as long as claiming :math:`n` Jobs at a time is faster than
claiming :math:`n` times 1 Job, and that the claiming process doesn't lock
the table for too long (which would prevent other Workers from operating
normally).

This can mitigate the overhead of submitting many small, fast-running Jobs
to the farm.  Bear in mind that increasing the batch size helps relieving
the pressure on the Job table from claiming Jobs *only*. As the Job table
is used to track the current status of jobs, it can also be slowed down by
running too many Workers, regardless of the batch size. And more generally,
the Jobs may create additional load on other databases, filesystems, etc,
which are *your* responsibility to monitor.

Optimizing the batch size is something of an art, as the optimal size is a
function of Job runtime and the number of Jobs in contention for the eHive
database.  Here follows some estimates of the optimal parameters to run a
single Analysis, composed of 1 million Jobs, under two scenarios:

 * Best *throughput*: the combination of parameters that gets all the Jobs
   done the fastest.
 * Best *efficiency*: the combination of parameters that has the highest
   capacity whilst maintaining an overhead per Job below 10 milliseconds.
   The overhead is defined as the average amount of time eHive spends per
   Job for general housekeeping tasks, but also for claiming. For instance,
   a Worker that has lived 660 seconds and run 600 Jobs (each set to sleep
   1 second) will have an overhead of 10 millisecond per Job. eHive has a
   minimum overhead per Job of 6-7 milliseconds.

In general, "best throughput" parameters put a lot more pressure on the
database. Only use these parameters if you are in a rush to get your
Analysis done, and if you are allowed to use that much resources from the
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
made of *Dummy* Jobs (they just sleep for a given amount of time) at
various capacities (1, 5, 10, 25, 50, 100, 200 or 250, 500, 1,000, 2,500, 5,000)
and batch sizes (1, 2, 5, 10, 20, 50, 100, 200, 500, 1,000, 2,000, 5,000),
for various sleep times. The notion of sleep models operations on other
databases (data processing with the Ensembl API, for instance), running a
system command, etc.  Although the
actual results are specific to the MySQL server used for the benchmark, the
trend is expected to be the same on other versions of MySQL.


Hive capacity vs Analysis capacity
++++++++++++++++++++++++++++++++++

*Analysis capacity*

    Limits the number of Workers that ``beekeeper.pl`` will run for this particular Analysis.
    It does not mean if you set it to 200 there will be exactly 200 workers of this Analysis,
    as there are other considerations taken into account by the scheduler, but there will be
    no more than 200.

*hive capacity*

    Also limits the number of Workers, but globally across the whole pipeline.
    If you set -hive_capacity of an Analysis to X it will mean "one Worker of this Analysis
    consumes 1/X of the whole Hive's capacity (which equals to 1.0)". Like
    Analysis capacity, setting it to 200 means that you will not get more
    than 200 running Workers.
    Using it only makes sense if you need several Analyses running in
    parallel and consuming the same resource (e.g. accessing the same
    table) to balance load between themselves.

If one of these is set to 0, eHive will not schedule any Workers for the
Analysis (regardless of the value of the other parameter). If a parameter
is not set (undefined), then its related limiter is unused.

Examples
~~~~~~~~

analysis_capacity=0 and hive_capacity is not set:

  No Workers are allowed to run

analysis_capacity=0 and hive_capacity=150:

  No Workers are allowed to run

analysis_capacity is not set and hive_capacity=0:

  No Workers are allowed to run

analysis_capacity is not set and hive_capacity=150:

  No Workers are allowed to run

analysis_capacity=150 and hive_capacity is not set:

  eHive will schedule at most 150 Workers for this Analysis

A.hive_capacity=1 and B.hive_capacity=300. Examples of allowed numbers of Workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 1          | 0          |
  +------------+------------+
  | 0          | 300        |
  +------------+------------+

A.hive_capacity=100, A.analysis_capacity=1 and B.hive_capacity=300. Examples of allowed numbers of Workers are:

  +------------+------------+
  | Analysis A | Analysis B |
  +============+============+
  | 1          | 297        |
  +------------+------------+
  | 0          | 300        |
  +------------+------------+

A.hive_capacity=100 and B.hive_capacity=300. Examples of allowed numbers of Workers are:

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

A.hive_capacity=100, B.hive_capacity=300 and B.analysis_capacity=210. Examples of allowed numbers of Workers are:

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

The Beekeeper is not constantly active: it works a bit, up to several seconds
depending on the size and complexity of the pipeline, and the
responsiveness of the job scheduler, and then sleeps for a given amount of
time (by default 1 minute, the ``-sleep`` parameter).  Every loop, the Beekeeper
submits ``-submit_workers_max`` Workers (which defaults to 50), to avoid
overloading the scheduler with submitted Jobs.

You can change both parameters, for instance reduce the sleep time to submit
Workers more frequently (e.g. 12 seconds == 0.2 minutes), or increase
``-submit_workers_max`` to submit more Workers every loop (e.g.  100 or
200) as long as the server supports it.  It is good practice to give
Workers time to check-in with the eHive database between loops. The default
parameters are safe values that generally work well for production
pipelines.

The impact of loop time on the overall time to complete a Workflow
will be fairly small, however. When a Worker completes a Job, it looks
for new Jobs that it can run, and will claim and run them automatically
- the Beekeeper is not involved in this claiming process. It's only in
the case where new Workers need to be created that the pipeline would
be waiting for another Beekeeper loop.


Other limiters
++++++++++++++

Besides the Analysis-level capacities, the number of running Workers is
limited by the ``TotalRunningWorkersMax`` parameter. This parameter has a
default value in the a hive_config.json file in the root of the eHive
directory and can be changed at the Beekeeper level with the ``--total_running_workers_max`` option.

Every time the Beekeeper loops, it will check the current state of your
eHive pipeline and the number of currently running Workers. If it
determines more Workers are needed, and the ``-total_running_workers_max``
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

