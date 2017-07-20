.. eHive guide to running pipelines: managing running pipelines

Tools and techniques for managing running pipelines
===================================================


Synchronizing ("sync"-ing) the pipeline database
------------------------------------------------

In order to function properly (to monitor the progress, block and
unblock analyses and send correct number of workers to the farm) the
eHive system needs to maintain certain number of job counters. These
counters and associated analysis states are updated in the process of
"synchronization" (or "sync"). This has to be done once before running
the pipeline, and normally the pipeline will take care of
synchronization by itself and will trigger the 'sync' process
automatically. However sometimes things go out of sync. Especially when
people try to outsmart the scheduler by manually stopping and running
jobs :) This is when you might want to re-sync the database. It is done
by running the
ensembl-hive/scripts/\ `**beekeeper.pl** <scripts/beekeeper.html>`__ in
"sync" mode:

::

            beekeeper.pl -url sqlite:///my_pipeline_database -sync


Re-balancing semaphores
-----------------------

