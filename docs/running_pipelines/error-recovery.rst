==============
Error Recovery
==============

When an eHive workflow encounters problems, it is often possible to correct the error and resume operation without having to restart from the beginning. Often, it is also possible to isolate problematic analyses while continuing to make progress through other branches of the workflow.

Considerations
==============

Although eHive provides a number of mechanisms to clean up after a failed job, there are some things it cannot do. It is the user's responsibility to understand what operations each runnable performs, and what changes they may have made. For example:

    - Files written to, changed, or deleted from a filesystem

    - Updates to non eHive database tables

Before resuming a workflow, the user should carefully check the state of any files or database tables involved with it.

Stopping pipeline execution
===========================

In general, it is a good idea to stop all pipeline execution before attempting to recover from errors. If an analysis has a problem, adding more jobs for that analysis could make the situation worse. Plus, a consistent state helps with accurate troubleshooting.

Take care to make sure all execution has ceased when stopping a pipeline. Remember, even though the beekeeper loop(s) have stopped, workers will continue until the end of their lifespan (when they run out of work or they reach their time limit).

The recommended way to stop workers is to set the analysis_capacity for analyses sharing their resource_class to zero. Setting analysis_capacity to zero will prevent any workers from claiming any new jobs from these analyses. Workers already running jobs will have an opportunity to exit as cleanly as possible under the circumstances, and possibly record useful information in the message log. This can be accomplished using the :ref:`tweak_pipeline.pl script <tweak-pipeline-script>`

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].analysis_capacity=0``

In some situations it may be necessary to take more drastic action to stop the workers in a pipeline. In order to do this, you may need to find the underlying processes and kill them using the command appropriate for your scheduler (e.g. bkill for LSF, qdel for PBS-like systems) - or using the kill command if the worker is running in the LOCAL meadow. It may help to look up the worker's process IDs in the worker table:

``db_cmd.pl -url sqlite://my_hive_db -sql 'SELECT process_id FROM worker WHERE status in ("JOB_LIFECYCLE", "SUBMITTED")'``

Isolating problematic analyses
==============================

It is possible to set eHive to bypass an analysis or a group of analyses. This can be useful for shutting off a problematic branch of a pipeline, while still allowing work to continue elsewhere. There are two primary ways to accomplish this:

    - One way is to set the analysis_capacity for an analysis to zero, as shown above. This will stop workers from claiming jobs in this analysis. However, any failed jobs will remain in their failed state until manually changed -- see :ref:`resetting-jobs` below -- so the beekeeper will refuse to loop if its -loop_until mode is set to respond to job failures.

    - Another way is to change the excluded state of an analysis. Setting is_excluded to 1 causes the analysis to be ignored by eHive in the following ways:

        - Workers will not claim jobs from an excluded analysis

        - The beekeeper will ignore FAILED jobs from that analysis and continue looping, unless its -loop_until is set to JOB_FAILURE.

    - In some cases, eHive will automatically set an analysis to excluded upon detecting certain error conditions, for example when the runnable cannot be compiled. In addition, an analysis can have its excluded state changed using tweak_pipeline.pl:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].is_excluded=1`` 

.. _resetting-jobs:

Resetting jobs and continuing execution
=======================================

Once the pipeline has been stopped, and the errors have been diagnosed and corrected (see `troubleshooting`), it's time to think about resuming the pipeline. There are a few steps likely to be needed to get the pipeline ready for restart.

Recall that, in order for eHive to start work, there must be at least one job in the READY state. After a pipeline shutdown, there may be branches of the pipeline that need to continue, but have no READY jobs. There are a few strategies to remedy this situation; which strategy to use depends on the particulars of the workflow, the analyses, and the reason the pipeline needs to be restarted. In general, READY state can be achieved through resetting jobs, clearing downstream semaphores by forgiving or discarding jobs, directly unblocking SEMAPHORED jobs, or seeding new jobs:

    - Resetting is the process of converting FAILED, DONE, and/or PASSED_ON jobs to READY. The user can reset all the jobs in an analysis using either the guiHive interface, or by using beekeeper.pl with the -reset_[done|failed|all]_jobs option. Individual jobs can be reset using beekeeper.pl with the -reset_job_id option. Resetting jobs in a fan will update the semaphore counts for the job(s) in the associated funnel.

    - Forgiving is the process of converting FAILED jobs to DONE. The user can forgive all FAILED jobs in an analysis using either the guiHive interface, or by using beekeeper.pl -forgive_failed_jobs. These jobs, once forgiven, will not be re-run. They also will not generate dataflow events. However, if these jobs are in a fan, forgiving will update the semaphore counts on associated funnel jobs.

    - Discarding is the process of converting READY jobs to DONE, without running them. The user can discard all READY jobs in an analysis using the guiHive interface, or by using beekeeper.pl -discard_ready_jobs. Note that discarding a job does not generate dataflow events. However, if these jobs are in a fan, discarding will update the semaphore counts on associated funnel jobs.

    - Unblocking is the process of converting SEMAPHORED jobs to READY. The user can unblock all SEMAPHORED jobs in an analysis using the guiHive interface, or by using beekeeper.pl -unblock_semaphored_jobs.

.. warning::

  It is best to reset, forgive, discard, or unblock jobs using either beekeeper.pl or the guiHive interface. Changing a job's state by simply updating the "status" column in the hive database is not recommended. Using beekeeper.pl or guiHive will ensure that eHive's internal bookkeeping details, such as semaphore counts, are properly updated.

.. note::

   When resetting jobs in a fan, remember to also reset any associated funnel jobs. The funnel jobs will be reset to SEMAPHORED state instead of DONE state.

If the analysis_capacities for any analyses were set to zero, they may need to be returned to their desired value. If there was no analysis_capacity for an analysis, and one is not desired, it can be removed by setting analysis_capacity to ``undef``:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].analysis_capacity=undef``

If an analysis was excluded by the user, or automatically by eHive upon detecting an error condition, it may be desirable to remove the exclusion. Alternatively, some analyses may need to be placed into an excluded state to allow the rest of the pipeline to continue. The tweak_pipeline.pl script can be used to both check the current excluded state of an analysis, and to change that state if necessary:

``tweak_pipeline.pl -url sqlite:///my_hive_db -SHOW analysis[logic_name].is_excluded  #check an analysis' excluded state``
 
``tweak_pipeline.pl -url sqlite:///my_hive_db -SET analysis[logic_name].is_excluded=1  #set an analysis' excluded state to excluded``
