
IO and Error Handling in Runnables
++++++++++++++++++++++++++++++++++

This section covers the details of programming a Runnable to accept and transmit data. Because a large component of handling errors is properly signalling that an error has occurred, along with the nature of that error, it will also be covered in this section. 

.. _parameters-in-jobs:

Parameter Handling
==================

Receiving input parameters
--------------------------

In eHive, parameters are the primary method of passing data and messages between components in a pipeline. Due to the central role of parameters, one of eHive's paradigms is to try to make most data sources look like parameters; somewhat analogous to the UNIX philosophy of "make everything look like a file." Therefore, the syntax for accessing parameters also applies to accessing Accumulators and user-defined tables in the eHive database.

Within a Runnable, parameter values can be set or retrieved using the ``param()`` method or one of its variants -- e.g. ``$self->param('parameter_name') #get`` or ``$self->param('parameter_name', $new_value) #set``:

   - ``param()`` - Sets or gets the value of the named parameter. When attempting to get the value for a parameter that has no value (this could be because it is not in scope), a warning "ParamWarning: value for param([parameter name]) is used before having been initialized!" will be logged.

   - ``param_required()`` - Like param(), except the Job will fail if the named parameter has no value.

   - ``param_exists()`` - True/false test for existence of a parameter with the given name. Note that this will return true if the parameter's value is undefined. Compare to ``param_is_defined()``.

   - ``param_is_defined()`` - True/false test for the existence of a parameter with the given name, and that the parameter has a value. This will return false if the parameter's value is undefined. Compare to ``param_exists()``.

Passing parameters within a Runnable
------------------------------------

It is often desirable to pass data between methods of a Runnable. For example, parameter values may need to be moved from ``fetch_input()`` into ``run()``, and the results of computation may need to be carried from ``run()`` into ``write_output()``. The eHive parameter mechanism is intended to facilitate this kind of data handling. Within a Runnable, new parameters can be created using ``$self->param()`` ( ``$self->param('parameter_name', $new_value)`` ) -- these are immediately available throughout the Runnable for the rest of the running Job's life cycle. Note that these parameters do not get carried over between Job runs - for example, if a Job fails and is retried, all parameters set in the Runnable are reset.

Parameter substitution
----------------------

.. note::

   Parameter substitution is explained in details in :ref:`parameters-substitution`.

Parameter substitution can also be called from any Job using ``$self->param_substitute($string)``.
The string will be evaluated (substituted) in the context of the Job's parameters. For instance,
assuming that the Job has a parameter named ``alpha``, the string ``the
value of alpha is #alpha#`` can be substituted.


As the substitution of parameters may fail, the definition of the above
param-like is expanded as follows:

  - ``param_exists($param_name)`` returns:

      - 1 if the parameter is present and can be substituted
      - *undef* if the parameter is present but the substitution failed
      - 0 if the parameter is absent

  - ``param_is_defined($param_name)`` returns:

      - 1 if the parameter is present and can be substituted to a
        **defined** value,
      - *undef* if the parameter is present but the substitution failed
      - 0 otherwise (i.e. the parameter is present but its value is
        *undef*, or the parameter is absent)

  - ``param($param_name)`` returns:

      - the value of the parameter if the parameter is present and can be substituted (i.e. if ``param_exists($param_name)`` returned 1)
      - *undef* otherwise.

  - ``param_required($param_name)`` is like ``param($param_name)`` but dies
    instead of returning *undef*, i.e.:

      - returns the parameter's value when ``param_is_defined($param_name)`` returns 1
      - dies otherwise.

Summary
-------

In practice, given this hash of parameters::

    {
        'a' => 3,
        'b' => undef,
        'c' => 0,
        'd' => '#other#',
        'aa' => '#a#',
        'bb' => '#b#',
        'cc' => '#c#',
    }

the API would return:

================== === ===== === ===== ==== ===== ==== =====
Parameter name      a    b    c    d    aa   bb    cc    x
================== === ===== === ===== ==== ===== ==== =====
param_exists()      1    1    1  undef   1   1      1    0
param_is_defined()  1    0    1  undef   1   0      1    0
param()             3  undef  0  undef   3  undef   0  undef
param_required()    3  (die)  0  (die)   3  (die)   0  (die)
================== === ===== === ===== ==== ===== ==== =====


Exporting data from a Runnable (dataflow)
=========================================

Dataflow events (:ref:`dataflows <dataflows>`) are a key part of eHive pipelines. They provide both a mechanism for signalling other pipeline components, as well as a mechanism for transmitting data. Functions are provided to allow Runnables to generate dataflow events with control over timing and data payload. These functions are covered in detail in the :ref:`runnable API documentation <runnable_api_dataflows>`.


Reading in data from external files and databases
=================================================

At a basic level, a Runnable is simply a Perl or Python module, which has access to all of the database and file IO facilities of any standard program. There are some extra facilities provided by eHive for convenience in working with external data sources:

   - Database URLs: Runnables can identify any MySQL PostgreSQL, or SQLite database using a URL, not just the eHive pipeline database. Runnable writers can obtain a database connection from a URL using the method ``Bio::EnsEMBL::Hive::Utils::go_figure_dbc()``.

   - Database connections handled through eHive's DBSQL modules automatically disconnect when inactive, and reconnect if disconnected.


Running external processes
==========================

   - The :doxehive:`Bio::EnsEMBL::Hive::Process` method ``run_system_command()`` is provided for convenience in spawning system processes from a Runnable and capturing the result.

Error Handling
==============

eHive provides a number of mechanisms to detect and handle error conditions. These include special dataflow events triggered by certain errors, similar to a try-catch system.

.. _resource-limit-dataflow:

Special Dataflow when Jobs Exceed Resource Limits
-------------------------------------------------

The eHive system can react when the job scheduler notifies it that a Job's memory requirements exceeded the Job's memory request (MEMLIMIT error), or when a Job's runtime exceeds the Job's runtime request (RUNLIMIT error). When receiving notification from the scheduler that a Job has been killed for one of those reasons, eHive will catch the error and perform the following actions:

   - The Job's status will be updated to PASSED_ON (instead of FAILED).

   - The Job will not be retried.

   - A dataflow event will be generated on branch -1 (for MEMLIMIT) or -2 (for RUNLIMIT). This event will pass along the same parameters and values that were passed to the original Job. The intent of this event is to seed a Job of a new Analysis that uses the same Runnable as the PASSED_ON Job, but with a different Resource Class. However, eHive does not enforce any special restrictions on this event -- it can be wired in the same way as any other Analysis.

Logging Messages
================

Runnables have STDOUT and STDERR output streams available, but these are redirected and function differently than they would in a conventional script. During normal eHive operation, when Jobs are run by Workers submitted via a Beekeeper loop, output to these streams is not sent to the shell in the conventional manner. Instead, it is either discarded to /dev/null, or is written to files specified by the ``-hive_log_dir`` option. Because of this redirection, STDERR and STDOUT should be treated as "verbose-level debug" output streams in Runnables. When a Job is run by a Worker started with the ``runWorker.pl`` script, or by using ``standaloneJob.pl``, then STDOUT and STDERR are handled normally (unless the ``-hive_log_dir option`` has been set, in which case output is directed to files in the directory specified by ``-hive_log_dir``).

When writing a Runnable, the preferred method for sending messages to the user is via the message log. An API is provided to facilitate logging messages in the log.

   - ``warning(message, message_class)`` causes the string passed in the message parameter to be logged. A message class (one of the valid classes for a message log entry) can optionally be added. For backwards compatibility, if a non-zero number is passed for message_class, this will be converted to WORKER_ERROR. 

   - Perl ``die`` messages are redirected to the message log, and will be classified as WORKER_ERROR.
