.. _error-recovery:

Error Recovery
++++++++++++++

When an eHive pipeline encounters problems, it is often possible to correct the error and resume operation without having to restart from the beginning. Often, it is also possible to isolate problematic Analyses while continuing to make progress through other branches of the workflow.

Considerations
==============

Although eHive provides a number of mechanisms to clean up after a failed Job, there are some things it cannot do. It is your responsibility to understand what operations each Runnable performs, and what changes they may have made. For example:

    - Files written to, changed, or deleted from a filesystem.

    - Updates to non-eHive database tables.

Before resuming a pipeline, you should carefully check the state of any files or database tables involved with it.

Stopping pipeline execution
===========================

In general, it is a good idea to stop all pipeline execution before attempting to recover from errors. If an Analysis has a problem, adding more Jobs for that Analysis could make the situation worse. Plus, a consistent state helps with accurate troubleshooting.

Take care to make sure all execution has ceased when stopping a pipeline. Remember, even though the Beekeeper loop(s) have stopped, Workers will continue until the end of their lifespan (when they run out of work or they reach their time limit).

The recommended way to stop Workers is to set the analysis_capacity for Analyses sharing their Resource Class to zero. Setting analysis_capacity to zero will prevent any Workers from claiming any new Jobs from these Analyses. Workers already running Jobs will have an opportunity to exit as cleanly as possible under the circumstances, and possibly record useful information in the message log. This can be accomplished using the :ref:`tweak_pipeline.pl script <tweak-pipeline-script>`

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].analysis_capacity=0``

In some situations it may be necessary to take more drastic action to stop the Workers in a pipeline. In order to do this, you may need to find the underlying processes and kill them using the command appropriate for your scheduler (e.g. ``bkill`` for LSF, ``scancel`` for SLURM) - or using the ``kill`` command if the Worker is running in the LOCAL meadow. It may help to look up the Worker's process IDs in the "worker" table:

``db_cmd.pl -url sqlite://my_hive_db -sql 'SELECT process_id FROM worker WHERE status in ("JOB_LIFECYCLE", "SUBMITTED")'``

If Workers are claiming batches of Jobs because an Analysis has a batch_size greater than one, it is possible to keep the Worker running on its current Job but "unclaim" any other Jobs in its current batch. This is done by setting the batch_size for the Analysis to 1. As long as each Job takes more than 20 seconds to complete, the Worker will re-check the batch size after finishing a Job.

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].batch_size=1``

Isolating problematic Analyses
==============================

It is possible to set eHive to bypass an Analysis or a group of Analyses. This can be useful for shutting off a problematic branch of a workflow, while still allowing work to continue elsewhere. There are two primary ways to accomplish this:

    - One way is to set the analysis_capacity for an Analysis to zero, as shown above. This will stop Workers from claiming Jobs in this Analysis. However, any failed Jobs will remain in their failed state until manually changed -- see :ref:`resetting-jobs` below -- so the Beekeeper will refuse to loop if its -loop_until mode is set to respond to Job failures.

    - Another way is to change the excluded state of an Analysis. Setting is_excluded to 1 causes the Analysis to be ignored by eHive in the following ways:

        - Workers will not claim Jobs from an excluded Analysis.

        - The Beekeeper will ignore FAILED Jobs from that Analysis and continue looping, unless its -loop_until is set to JOB_FAILURE.

    - In some cases, eHive will automatically set an Analysis to excluded upon detecting certain error conditions, for example when the Runnable cannot be compiled. In addition, an Analysis can have its excluded state changed using ``tweak_pipeline.pl``:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].is_excluded=1`` 

.. _resetting-jobs:

Resetting Jobs and continuing execution
=======================================

Once pipeline execution has been stopped, and the errors have been diagnosed and corrected (see `troubleshooting`), it's time to think about resuming execution. There are a few steps likely to be needed to prepare the pipeline for restart.

Recall that, in order for eHive to start work, there must be at least one Job in the READY state. After a pipeline shutdown, there may be branches of the pipeline that need to continue, but have no READY Jobs. There are a few strategies to remedy this situation; which strategy to use depends on the particulars of the workflow, the Analyses, and the reason the pipeline needs to be restarted. In general, READY state can be achieved through resetting Jobs, clearing downstream semaphores by forgiving or discarding Jobs, directly unblocking SEMAPHORED Jobs, or seeding new Jobs:

    - Resetting is the process of converting FAILED, DONE, and/or PASSED_ON Jobs to READY. You can reset all the Jobs in an Analysis using either the guiHive interface, or by using ``beekeeper.pl`` with the ``-reset_[done|failed|all]_jobs`` option. Individual Jobs can be reset using ``beekeeper.pl`` with the ``-reset_job_id`` option. Resetting Jobs in a fan will update the semaphore counts for the Job(s) in the associated funnel.

    - Forgiving is the process of converting FAILED Jobs to DONE. You can forgive all FAILED Jobs in an Analysis using either the guiHive interface, or by using ``beekeeper.pl -forgive_failed_jobs``. These Jobs, once forgiven, will not be re-run. They also will not generate dataflow events. However, if these Jobs are in a fan, forgiving will update the semaphore counts on associated funnel Jobs.

    - Discarding is the process of converting READY Jobs to DONE, without running them. You can discard all READY Jobs in an Analysis using the guiHive interface, or by using ``beekeeper.pl -discard_ready_jobs``. Note that discarding a Job does not generate dataflow events. However, if these Jobs are in a fan, discarding will update the semaphore counts on associated funnel Jobs.

    - Unblocking is the process of converting SEMAPHORED Jobs to READY. You can unblock all SEMAPHORED Jobs in an Analysis using the guiHive interface, or by using ``beekeeper.pl -unblock_semaphored_jobs``.

.. warning::

  It is best to reset, forgive, discard, or unblock Jobs using either ``beekeeper.pl`` or the guiHive interface. Changing a Job's state by simply updating the "status" column in the eHive database is not recommended. Using ``beekeeper.pl`` or guiHive will ensure that eHive's internal bookkeeping details, such as semaphore counts, are properly updated.

.. note::

   When resetting Jobs in a fan, remember to also reset any associated funnel Jobs. The funnel Jobs will be reset to SEMAPHORED state instead of DONE state.

If the analysis_capacities for any Analyses were set to zero, they may need to be returned to their desired value. If there was no analysis_capacity for an Analysis, and one is not desired, it can be removed by setting analysis_capacity to ``undef``:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].analysis_capacity=undef``

If you excluded an Analysis, or eHive automatically excluded one upon detecting an error condition, it may be desirable to remove the exclusion. Alternatively, some Analyses may need to be placed into an excluded state to allow the rest of the pipeline to continue. The ``tweak_pipeline.pl`` script can be used to both check the current excluded state of an Analysis, and to change that state if necessary:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SHOW analysis[logic_name].is_excluded  #check an analysis' excluded state``
 
``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].is_excluded=1  #set an analysis' excluded state to excluded``
