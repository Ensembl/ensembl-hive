
Runnable API
============

eHive exposes an interface for Runnables (jobs) to interact with the
system:

  - query their own parameters (see :ref:`parameters-in-jobs`),
  - control its own execution and report issues,
  - run system commands,
  - trigger some *dataflow* events (e.g. create new jobs).


Reporting and logging
---------------------

Jobs can log messages to the standard output with the
``$self->say_with_header($message, $important)`` method. However they are only printed
when the *debug* mode is enabled (see below) or when the ``$important`` flag is switched on.
They will also be prefixed with a standard prefix consisting of the
runtime context (Worker, Role, Job).

The debug mode is controlled by the ``--debug X`` option of
:ref:`script-beekeeper` and :ref:`script-runWorker`. *X* is an integer,
allowing multiple levels of debug, although most of the modules will only
check whether it is 0 or not.

``$self->warning($message)`` calls ``$self->say_with_header($message, 1)``
(so that the messages are printed on the standard output) but also stores
them in the database (in the ``log_message`` table).

To indicate that a Job has to be terminated earlier (i.e. before reaching
the end of ``write_output``), you can call:

- ``$self->complete_early($message)`` to mark the Job as *DONE*
  (successful run) and record the message in the database. Beware that this
  will trigger the *autoflow*.
- ``$self->complete_early($message, $branch_code)`` is a variation of the
  above that will replace the autoflow (branch 1) with a dataflow on the
  branch given.
- ``$self->throw($message)`` to log a failed attempt. The Job may be given
  additional retries following the analysis' *max_retry_count* parameter,
  or is marked as *FAILED* in the database.

System interactions
-------------------

All Runnables have access to the ``$self->run_system_command`` method to run
arbitrary system commands (the ``SystemCmd`` Runnable is merely a wrapper
around this method).

``run_system_command`` takes two arguments:

#. The command to run, given as a single string or an arrayref. Arrayrefs
   are the preferred way as they simplify the handling of whitespace and
   quotes in the command-line arguments. Arrayrefs that correspond to
   straightforward commands, e.g. ``['find', '-type', 'd']``, are passed to
   the underlying ``system`` function as lists. Arrayrefs can contain shell
   meta-characters and delimiters such as ``>`` (to redirect the output to a
   file), ``;`` (to separate two commands that have to be run sequentially)
   or ``|`` (a pipe) and will be quoted and joined and passed to ``system``
   as a single string.
#. An hashref of options. Accepted options are:

   - ``use_bash_pipefail``: Normally, the exit status of a pipeline (e.g.
     ``cmd1 | cmd2`` is the exit status of the last command, meaning that
     errors in the first command are not captured. With the option turned
     on, the exit status of the pipeline will capture errors in any command
     of the pipeline, and will only be 0 if *all* the commands exit
     successfully.
   - ``use_bash_errexit``: Exit immediately if a command fails. This is
     mostly useful for cases like ``cmd1; cmd2`` where by default, ``cmd2``
     would always be executed, regardless of the exit status of ``cmd1``.
   - ``timeout``: the maximum number of seconds the command is allowed to
     run for. The exit status will be set to -2 if the command had to be
     aborted.

During their execution, jobs may certainly have to use temporary files.
eHive provides a directory that will exist throughout the lifespan of the
Worker with the ``$self->worker_temp_directory`` method. The directory is created
the first time the method is called, and deleted when the Worker ends. It is the Runnable's
responsibility to leave the directory in a clean-enough state for the next
Job (by removing some files, for instance), or to clean it up completely
with ``$self->cleanup_worker_temp_directory``.

By default, this directory will be put under /tmp, but it can be overriden
by adding a ``worker_temp_directory_name`` method to the runnable. This can
be used to:

- use a faster filesystem (although /tmp is usually local to the machine),
- use a network filesystem (needed for distributed applications, e.g. over
  MPI). See :ref:`worker_temp_directory_name-mpi` in the :ref:`howto-mpi` section.

.. _runnable_api_dataflows:

Dataflows
---------

eHive is an *event-driven* system whereby agents trigger events that
are immediately reacted upon. The main event is called "dataflow" (see
:ref:`dataflows` for more information). A dataflow event is made up of
two parts: An event, which is identified by a "branch number", with an
attached data payload, consisting of parameters. A Runnable can create
as many events as desired, whenever desired. The branch number can be
any integer, but note that "-2", "-1", "0", and "1" have special meaning
within eHive. -2, -1, and 0 are special branches for
:ref:`error handling <resource-limit-dataflow>`, and 1 is the autoflow branch.

.. warning::

    If a Runnable explicitly generates a dataflow event on branch 1, then
    no autoflow event will be generated when the Job finishes. This is
    unusual behaviour -- many pipelines expect and depend on autoflow
    coinciding with Job completion. Therefore, you should avoid explicitly
    creating dataflow on branch 1, unless no alternative exists to produce
    the correct logic in the Runnable. If you do override the autoflow by
    creating an event on branch 1, be sure to clearly indicate this in the
    Runnable's documentation.

Within a Runnable, dataflow events are performed via the ``$self->dataflow_output_id($data,
$branch_number)`` method.

The payload ``$data`` must be of one of these types:

- A hash-reference that maps parameter names (strings) to their values,
- An array-reference of hash-references of the above type, or
- ``undef`` to propagate the Job's input_id.

If no branch number is provided, it defaults to 1.

Runnables can also use ``dataflow_output_ids_from_json($filename, $default_branch)``.
This method simply wraps ``dataflow_output_id``, allowing external programs
to easily generate events. The method takes two arguments:

#. The path to a file containing one JSON object per line. Each line can be
   prefixed with a branch number (and some whitespace), which will override
   the default branch number.
#. The default branch number (defaults to 1).

Use of this is demonstrated in the Runnable :doxehive:`Bio::EnsEMBL::Hive::RunnableDB::SystemCmd`
