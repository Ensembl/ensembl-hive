.. eHive guide to running pipelines: running a pipeline, running jobs

Running a pipeline and running Jobs
===================================

.. index:: Pipeconfig

Several eHive scripts exist to create and execute Jobs once an instance of a
pipeline has been initialised.

.. _seeding-jobs-into-the-pipeline-database:

Seeding Jobs into the pipeline database
---------------------------------------

An eHive pipeline database contains a dynamic collection of Jobs (tasks) to be done.
Jobs can be added to the collection by the user (we call this process
"seeding"), during pipeline initialisation, or dynamically by already running
Jobs. When a database is created using :ref:`init_pipeline.pl
<script-init_pipeline>` it may or may not already be seeded, depending on the
PipeConfig file. (One way to check whether Jobs have been automatically seeded
is to look at the flow diagram using guiHive or :ref:`generate_graph.pl <script-generate_graph>`).
If the pipeline needs seeding, this is done using the :ref:`seed_pipeline.pl
<script-seed_pipeline>` script, specifying both the Analysis to be seeded and
the parameters of the Job being created:

::

            seed_pipeline.pl -url sqlite:///my_pipeline_database -logic_name "analysis_name" -input_id '{ "paramX" => "valueX", "paramY" => "valueY" }'

It only makes sense to seed certain Analyses; in particular ones that do not have
any incoming dataflow.


Running Jobs with the Beekeeper
-------------------------------

eHive's :ref:`beekeeper.pl <script-beekeeper>` script (the "Beekeeper") is the
primary way to execute work in a pipeline. The Beekeeper is responsible for
counting the number of Jobs ready to be run, comparing that to the current
Worker population, and creating Workers if needed. These Workers then claim
Jobs and execute them.

Usually, ``beekeeper.pl`` is run in a continuously looping mode, specified by
passing the ``-loop`` option. In this mode, it checks the status of the pipeline
and creates Workers if needed once per minute, sleeping between loops. If
desired, the interval between loop iterations can be adjusted with the
``-sleep [minutes]`` option. Our experience is that the default one minute loop
interval is usually correct for most applications, but a faster interval may be
useful for testing or debugging a pipeline.

For example to run the Beekeeper in loop mode, looping every six seconds, invoke
the Beekeeper as follows:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -loop -sleep 0.1

Because the Beekeeper should be running for the entire time the pipeline is
executing, it is good practice to run it in a detachable terminal, such as
`screen <https://www.gnu.org/software/screen/>`__ or `tmux <https://tmux.github.io/>`__.

It is also possible to run just a single iteration of the Beekeeper loop, which
can be useful for testing during pipeline development. This is done by giving
the ``-run`` flag on the command line:

::

          beekeeper.pl -url sqlite:///my_pipeline_database -run


Beekeeper loop_until modes
--------------------------

The Beekeeper will continue looping until it detects the pipeline is in a state
where it should stop. The user can specify the set of conditions that the
Beekeeper will check for by setting the ``-loop_until`` option to one of the
following values:

#. ``ANALYSIS_FAILURE`` (this is the Beekeeper's default behaviour if no other ``-loop_until`` mode is set). In this mode, the Beekeeper will loop until one of two conditions are met:

    #. There are no more :hivestatus:`<READY>[ READY ]` Jobs, or
    #. The fraction of :hivestatus:`<FAILED>[ FAILED ]` Jobs for a particular analysis exceeds that Analysis' fault tolerance.

#. ``JOB_FAILURE`` In this mode, the Beekeeper will loop until any Job fails, regardless of the fault tolerance of that Job's Analysis.
#. ``NO_WORK`` In this mode, the Beekeeper will loop until there is no work left to do (no Jobs in :hivestatus:`<READY>[ READY ]` state). In this mode, Job failures are ignored.
#. ``FOREVER`` In this mode, the Beekeeper will loop continuously until stopped by the user (e.g. by ``Ctrl-C`` or the UNIX ``kill`` command), ignoring errors.


Running a single Job using runWorker.pl
---------------------------------------

eHive's :ref:`runWorker.pl <script-runWorker>` script creates a single Worker
which can run ready Jobs. This script is particularly useful for testing or
debugging, since the Worker's running conditions can be tightly controlled, and
because printed output from the Worker will be directed to the terminal where
it is running.

At a minimum, ``runWorker.pl`` needs to know which database its Worker
should run against. As usual this can be provided several different ways:

  - It can be passed in as a pipeline url using the ``-url`` command line option,
  - It can be provided as part of a registry file, passed in using ``-reg_conf``.

Several additional command-line options are available to specify which Jobs the
Worker will claim. These include:

  - ``-job_id [id]`` constrains the Worker to run a specific Job from the database's jobs table.
  - ``-analyses_pattern [pattern]`` constrains the Worker to run Jobs from Analyses with logic names matching the given pattern. The pattern can include SQL-style wildcards. For example ``-analyses_pattern 'blast%-4..6'``.
  - ``-rc_name [name]`` and ``-rc_id [id]`` constrain the Worker to run Jobs from Analyses having the resource class specified by name or id respectively. Importantly, this does *not* specify the Resource Class of the Worker, it only restricts which Jobs the Worker will claim.
  - ``-force`` will force the Worker to run a Job, even if the Job is not READY (for example :hivestatus:`<BLOCKED>[ BLOCKED ]`, :hivestatus:`<DONE>[ DONE ]`, or :hivestatus:`<SEMAPHORED>[ SEMAPHORED ]`). Usually used in conjunction with ``-job_id [id]``.

Some other options that can be useful for testing or debugging Jobs are:

  - ``-no_cleanup`` to have the Worker not clean up files it may have placed in the temp directory.
  - ``-no_write`` prevents the Worker from executing any code in the Runnable's write_output() method, and stops autoflow on branch 1.
  - ``-worker_log_dir [path]`` directory where STDOUT and STDERR for this Worker should be directed.
  - ``-hive_log_dir [path]`` directory where STDOUT and STDERR for all Workers should be directed. For ``runWorker.pl`` this is functionally equivalent to ``-worker_log_dir``.
  - ``-retry_throwing_jobs`` retry a job if it knowingly throws an error.
