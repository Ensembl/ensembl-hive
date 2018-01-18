.. eHive guide to running pipelines: running a pipeline, running jobs

Running a pipeline and running jobs
===================================

.. index:: Pipeconfig

Several eHive scripts exist to create and execute jobs once an instance of a
pipeline has been initialized.

.. _seeding-jobs-into-the-pipeline-database:

Seeding jobs into the pipeline database
---------------------------------------

A pipeline database contains a dynamic collection of jobs (tasks) to be done.
The jobs can be added to the "blackboard" by the user (we call this process
"seeding"), during pipeline initialization, or dynamically by already running
jobs. When a database is created using :ref:`init_pipeline.pl <script-init_pipeline>`
it may or may not already be seeded, depending on the PipeConfig file. (One way
to check whether jobs have been automatically seeded is to look at the flow
diagram using GuiHive or generate_graph.pl). If the pipeline needs seeding, this
is done using :ref:`seed_pipeline.pl <script-seed_pipeline>` script, specifying
providing both the Analysis to be seeded and the parameters of the job being
created:

::

            seed_pipeline.pl -url sqlite:///my_pipeline_database -logic_name "analysis_name" -input_id '{ "paramX" => "valueX", "paramY" => "valueY" }'

It only makes sense to seed certain analyses; in particular ones that do not have
any incoming dataflow on the flow diagram.


Running jobs with the beekeeper
-------------------------------

eHive's :ref:`beekeeper.pl <script-beekeeper>` script (the "beekeeper") is the
primary way to execute work in a pipeline. The beekeeper is responsible for
counting the number of jobs ready to be run, comparing that to the current
worker population, and creating workers if needed. These workers then claim
jobs and execute them.

Usually, beekeeper.pl is run in a continuously looping mode, specified by
passing the ``-loop`` option. In this mode, it checks the status of the pipeline
and creates workers if needed once per minute, sleeping between loops. If
desired, the interval between loop iterations can be adjusted with the
``-sleep [minutes]`` option. Our experience is that the default one minute loop
interval is usually correct for most applications, but a faster interval may be
useful for testing or debugging a pipeline

For example to run the beekeeper in loop mode, looping every six seconds:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -loop -sleep 0.1

Because the beekeeper should be running for the entire time the pipeline is
executing, it is good practice to run it in a detachable terminal, such as
screen or tmux.

It is also possible to run just a single iteration of the beekeeper loop. This
is done by giving the ``-run`` flag on the command line:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -run

This mode can be useful for testing during pipeline development.

Beekeeper loop_until modes
--------------------------

The beekeeper will continue looping until it detects the pipeline is in a state
where it should stop. The user can specify the set of conditions that the
beekeeper will check for by setting the ``-loop_until`` option to one of the
following values:

#. ``ANALYSIS_FAILURE`` (this is the beekeeper's default behaviour if no other ``-loop_until`` mode is set). In this mode, the beekeeper will loop until one of two conditions are met:

    #. There are no more :hivestatus:`<READY>[ READY ]` jobs.
    #. The fraction of :hivestatus:`<FAILED>[ FAILED ]` jobs for a particular analysis exceeds that analysis' fault tolerance.

#. ``JOB_FAILURE`` In this mode, the beekeeper will loop until any job fails, regardless of the fault tolerance of that job's analysis.
#. ``NO_WORK`` In this mode, the beekeeper will loop until there is no work left to do (no jobs in :hivestatus:`<READY>[ READY ]` state). In this mode, job failures are ignored.
#. ``FOREVER`` In this mode, the beekeeper will loop continuously until stopped by the user (e.g. by ``Ctrl-C`` or the UNIX ``kill`` command), ignoring errors.


Running a single job using runWorker.pl
---------------------------------------

eHive's :ref:`runWorker.pl <script-runWorker>` script creates a single worker
which can run ready jobs. This script is particularly useful for testing or
debugging, since the workers running conditions can be tightly controlled, and
because printed output from the worker will be directed to the terminal where
it is running.

At a minimum, runWorker.pl needs to know which pipeline database its worker
should run against. As usual this can be provided several different ways:

  - It can be passed in as a pipeline url using the ``-url`` command line option
  - It can be provided as part of a registry file, passed in using ``-reg_conf``, ``-regfile``, or ``-reg_file``

Several additional command-line options are available to specify which jobs the
worker will claim. These include:

  - ``-job_id [id]`` constrains the worker to run a specific job from the pipeline databases job's table.
  - ``-analyses_pattern [pattern]`` constrains the worker to run jobs from analyses with logic names matching the given pattern. The pattern can include SQL-style wildcards. For example ``-analyses_pattern 'blast%-4..6'``
  - ``-rc_name [name]`` and ``-rc_id [id]`` constrain the worker to run jobs from analyses having the resource class specified by name or id respectively. Importantly, this does **not** specify the resource class of the worker, it only restricts which jobs the worker will claim.
  - ``-force 1`` will force the worker to run a job, even if the job is not READY (for example :hivestatus:`<BLOCKED>[ BLOCKED ]`, :hivestatus:`<DONE>[ DONE ]`, or :hivestatus:`<SEMAPHORED>[ SEMAPHORED ]`). Usually used in conjunction with ``-job_id [id]``.

Some other options that can be useful for testing or debugging jobs are:

  - ``-no_cleanup`` to have the worker not clean up files it may have placed in the temp directory
  - ``-no_write`` prevents the worker from executing any code in the runnable's write_output() method, and stops autoflow on branch 1
  - ``-worker_log_dir [path]`` directory where STDOUT and STDERR for this worker should be directed
  - ``-hive_log_dir [path]`` directory where STDOUT and STDERR for all hive workers should be directed. For runWorker.pl this is functionally equivalent to ``-worker_log_dir``.
  - ``-retry_throwing_jobs 1`` retry a job if it knowingly throws an error
