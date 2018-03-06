
Runnable API
============

eHive exposes an interface for Runnables (jobs) to interact with the
system:

  - query their own parameters. See :ref:`parameters-in-jobs`
  - control its own execution
  - report issues
  - run commands
  - trigger some *dataflow* events (e.g. create new jobs)


Execution control
-----------------

- worker_temp_directory
- worker_temp_directory_name
- cleanup_worker_temp_directory

Reporting and logging
---------------------

- warning
- say_with_header
- throw
- complete_early
- debug

System commands
---------------

- run_system_command

Dataflows
---------

eHive is an *event-driven* system whereby agents trigger events that
are immediately reacted upon. The main event is called **Dataflow** (see
:ref:`dataflows` for more information) and
consists of sending some data somewhere. The destination of a Dataflow
event must be defined in the pipeline graph itself, and is then referred to
by a *branch number* (see :ref:`dataflows`).

Within a Runnable, Dataflow events are performed via the ``$self->dataflow_output_id($data,
$branch_number)`` method.

The payload ``$data`` must be of one of these types:

- Hash-reference that maps parameter names (strings) to their values.
- Array-reference of hash-references of the above type
- ``undef`` to propagate the job's input_id

The branch number defaults to 1 and can be skipped. Generally speaking, it
has to be an integer.

Runnables can also use ``dataflow_output_ids_from_json($filename, $default_branch)``.
This method simply wraps ``dataflow_output_id``, allowing external programs
to easily generate events. The method takes two arguments:

#. The path to a file containing one JSON object per line. Each line can be
   prefixed with a branch number (and some whitespace), which will override
   the default branch number.
#. The default branch number (defaults to 1 too)


