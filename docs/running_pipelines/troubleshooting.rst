
Troubleshooting
+++++++++++++++

There are many reasons an eHive pipeline could encounter problems including:

   - Incomplete or incorrect setup of the eHive system or its associated environment,

   - Problems with the local compute environment,

   - Problems with the underlying data,

   - Lack of availability of resources,

   - Bugs in the eHive system.

In this section, we will describe the tools eHive provides to help diagnose faults. In addition, this section will cover general troubleshooting strategies, and list common problems along with their solutions. See the section on :ref:`error recovery <error-recovery>` for details on how to resume a pipeline once a fault has been diagnosed and corrected.

Tools
=====

Several tools are included in eHive to show details of a pipeline's execution:

   - The message log,

   - The hive log directory and submission log directory, which contain:

      - Beekeeper log files,

      - Worker log files.

   - The :ref:`runWorker.pl <script-runWorker>` script, allowing one Worker to run and produce output in a defined environment,

   - The :ref:`standaloneJob.pl <script-standaloneJob>` script, allowing a Runnable to be executed independently of a pipeline.


Message log
-----------

The message log stores messages sent from the Beekeeper and from Workers. Messages in the log are not necessarily indications of trouble. Broadly speaking, they can be categorised into two classes: information messages or error messages. In eHive prior to version 2.5, those were the only two classes available -- indicated by either a 0 or 1 value respectively stored in the is_error column. Starting in eHive version 2.5, the is_error column was replaced with message_class, which expanded the categories available for messages to:

   - INFO

       - INFO class messages provide information on run progress, details about the operation of a Job, and record certain internal bookkeeping data (such as Beekeeper "heartbeats").

   - PIPELINE_CAUTION

      - PIPELINE_CAUTION messages are sent when an abnormal condition is detected in a component that affects the entire pipeline, but the condition is not serious enough to stop pipeline execution. Examples of conditions that can generate PIPELINE_CAUTION messages include inconsistencies in semaphore counts, or transient failures to connect the eHive database.

   - PIPELINE_ERROR

      - PIPELINE_ERROR messages are sent when an abnormal condition is detected in a component that affects the entire pipeline, and the condition is serious enough to stop pipeline execution.

   - WORKER_CAUTION

      - WORKER_CAUTION messages are sent when a Worker encounters an abnormal condition relating to its particular lifecycle or Job execution, but the condition is not serious enough to end the Worker's lifecycle. Examples of conditions that can generate WORKER_CAUTION messages include a preregistered Worker taking a long time to contact the database, or problems updating a Worker's resource usage.

   - WORKER_ERROR

      - WORKER_ERROR messages are sent when a Worker encounters an abnormal condition related to its particular lifecycle of Job execution, and that condition causes it to end prematurely. Examples of conditions that can generate WORKER_ERROR messages include failure to compile a Runnable, reasons why Workers disappeared (as detected in the :ref:`Garbage collection<garbage-collection>` phase, or a Runnable generating a failure message.

The log can be viewed in guiHive's log tab, or by directly querying the eHive database. In the database, the log is stored in the log_message table. To aid with discovery of relevant messages, eHive also provides via a view called msg, which includes Analysis logic_names. For example, to find all non-INFO messages for an Analysis with a logic_name of "align_sequences" one could run:

``db_cmd.pl -url sqlite:///my_hive_db -sql 'SELECT * FROM msg WHERE logic_name="align_sequences" AND message_class != "INFO"'``

.. _hive-log-directory:

Hive log directory
------------------

In addition to the message log, eHive is equipped to produce additional debugging output and capture that output in an organised collection of files. There are two options to ``beekeeper.pl`` which turn on this output capture: ``-submit_log_dir`` and ``-hive_log_dir``.

   - ``-submit_log_dir [directory]`` stores the Job manager's STDERR and STDOUT output (e.g. the output from LSF's -e and -o options) in an collection of directories created under the specified directory. There is one directory per Beekeeper per iteration. Each Job submission's output is stored in a file named log_default_[pid].[err|out]. If the process is part of a job array, the array index is separated from the pid by an underscore (so -o output for array job 12345[9] would be stored in file log_default_12345_9.out).

   - ``-hive_log_dir [directory]`` stores STDERR and STDOUT from each Worker. This includes anything explicitly output in a Runnable (e.g. with a Perl print or warn statement), as well as information generated by the Worker as it goes through its lifecycle. There is one directory per Worker created under the specified directory, indexed by Worker ID. Two files are created in each Worker's directory: worker.err and worker.out storing STDERR and STDOUT respectively.

.. note::

  It is generally safe to restart a Beekeeper, or start multiple Beekeepers for a pipeline, and have them log to the same ``-submit_log_dir`` and/or ``-hive_log_dir``. In the case of ``-submit_log_dir``, each subsequent Beekeeper will increment the Beekeeper number for the submit output directory. For example, the first Beekeeper run on a pipeline will start by creating directory submit_bk1_iter1 for the first loop, followed by submit_bk1_iter2 for the second iteration. A second Beekeeper started on that same pipeline will create a submit directory submit_bk*2*_iter1 for its first iteration and so on. Worker IDs will also automatically increment within the same pipeline, preventing Worker directory names from colliding.

  However, if a pipeline is re-initialised using ``init_pipeline.pl``, then all Beekeeper and Worker identifiers will restart from 1. In that case, ``-submit_log_dir`` and ``-hive_log_dir`` will overwrite files and directories within the specified directory.

The runWorker.pl script
-----------------------

The :ref:`runWorker.pl script <script-runWorker>` can be useful for observing the execution of a Job or Analysis within the context of a pipeline. This script directly runs a Worker process in the environment (machine and environment variables) of the command line where it is run. When running a Job using ``runWorker.pl``, STDERR and STDOUT can be viewed in the terminal, or redirected in the usual way. There are many command-line options to control the behaviour of ``runWorker.pl`` -- the following are a few that may be useful when invoking ``runWorker.pl`` to diagnose problems with a particular Job or Analysis:

   - ``-analyses_pattern`` and ``-analysis_id`` can be used to restrict the Worker to claiming Jobs from a particular Analysis or class of Analyses. Note that there is no guarantee of which Job out of the Jobs in those Analyses will be claimed. It could be any READY Job (or even a non-READY Job if ``-force`` is also specified).

   - ``-job_id`` runs a specific Job identified by Job ID, provided that the Job is in a READY state or ``-force`` is also specified.

   - Combine any of the above with ``-force`` to force a Worker to run a Job even if the Job is not READY and/or the Analysis is BLOCKED or EXCLUDED.

   - ``-job_limit`` can be set to limit the number of Jobs the Worker will claim and run. Otherwise, the Worker started by ``runWorker.pl`` will run until the end of its lifespan, possibly respecializing to claim Jobs from different Analyses if ``-can_respecialize`` should happen to also be set on the command line. 

   - ``-hive_log_dir`` works with ``runWorker.pl`` in the same way as with ``beekeeper.pl``. See :ref:`hive-log-directory` for details.

   - ``-worker_log_dir`` will output STDERR and STDOUT into a log directory. Note that this will simply create a file called worker.out in the specified directory. If a Worker is run multiple times with ``-worker_log_dir`` set to the same directory, only the output from the most recent ``runWorker.pl`` will be in worker.out.

   - ``-no_cleanup`` will leave temporary files in the temporary directory (usually /tmp).

   - ``-no_write`` will prevent write_output() from being called in Runnables.

The standaloneJob.pl script
---------------------------

The :ref:`standaloneJob.pl <script-standaloneJob>` script executes a particular Runnable, and allows that execution to be partially or completely detached from any existing pipeline. This can be useful to see in detail what a particular Runnable is doing, or for checking parameter values. There are many command-line options to control the behaviour of ``standaloneJob.pl`` -- the following are a few that may be useful when invoking ``standaloneJob.pl`` to diagnose problems with a particular Job or Analysis:

   - ``-url`` combined with ``-job_id`` allows ``standaloneJob.pl`` to "clone" a Job that already exists in an eHive database. When these options are given, ``standaloneJob.pl`` will copy the parameters of the "donor" Job specified by ``-job_id`` from the database specified by ``-url``, and use those parameters to create and run a new Job of the "donor" Job's Analysis type. Note that this new Job is *not* part of the pipeline. In particular

      - No new Job will be created in the "job" table.

      - The status of the "cloned" Job will not be changed.

      - Dataflow events will not be passed into the pipeline (unless explicitly directed there using ``-flow_into``).

   - Also note, when "cloning" a Job with ``-url`` and ``-job_id``, the state of the "donor" Job is ignored. It is entirely possible to specify the Job ID of a FAILED, SEMAPHORED, READY, or any other state of Job. The ``standaloneJob.pl`` script will still copy the parameters and attempt to run a Job of that Analysis type.

   - ``-no_cleanup`` will leave temporary files in the temporary directory (usually /tmp).

   - ``-no_write`` will prevent write_output() from being called in the Runnable.

.. warning::

  If the Runnable interacts with files or non-eHive databases, it may still do so when running as a standalone Job. Take care that important data is not overwritten or deleted in this situation. 


Techniques
==========

   - The first indication of problems with a pipeline generally appear in ``beekeeper.pl`` output and in guiHive, in the form of failed Jobs.

   - Analyses with failed Jobs, and Analyses immediately adjacent to them are good places to start looking for informative messages in the message log.

   - When running on a farm, it is possible that certain nodes or groups of nodes are problematic for some reason (e.g. failure to mount NFS shares). The "worker" table in the database keeps track of which nodes the Worker was submitted to in the meadow_host column. It is sometimes worth checking to see if there is a common node amongst failed Workers. Workers are associated with Jobs via the role table, so a query can be constructed to see if failed Jobs share a common node or nodes. 

   - If the failing Analysis reads from or writes to the filesystem or another database, checking the relevant files or database tables may reveal clues to the cause of the failure.

   - Remember that ``beekeeper.pl`` accepts the ``-analyses_pattern`` option, limiting Workers it submits to working on Jobs from a specific subset of Analyses. This can be useful when restarting the Beekeeper using ``-hive_log_dir`` to get detailed information about a problematic Analysis or Analyses.
