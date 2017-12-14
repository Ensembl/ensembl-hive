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
