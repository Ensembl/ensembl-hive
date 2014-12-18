
# Introduction

eHive provides a generic interface to interact with runnables written in
languages other than Perl. This is mainly a communication protocol based on
JSON, and managed by the Perl module `Bio::EnsEMBL::Hive::GuestProcess`.

Support must come in two parts:
* a wrapper that GuestProcess will launch, which will in turn run the
  user's Runnable
* a port of eHive's Runnable API to the new language, which people can use
  in their Runnables

eHive now supports a number of new languages, but we sill encourage eHive
users to add support for their favourite one. This documents explains all
aspects of the implementation in details, and other implementations can be
used as a reference.

# Interface for wrappers

> In this section, `${language}` is the name of the programming
> language, `${module_name}` is the name of the user's runnable

eHive natively supports a few langues (see `ensembl-hive/wrappers/`) but
can also use wrappers that exist in the user's environment.
Wrappers can be declared through the environment variable
`EHIVE_WRAPPER_XXX` where `XXX` is the name of the language in upper case.

Wrappers work in two modes:
* `${executable} ${module_name} compile`
* `${executable} ${module_name} run ${fd_in} ${fd_out}`

The `compile` mode is used to check that the Runnable can be loaded and is a
valid eHive Runnable. The return code must be 0 upon success, or 1 otherwise.

The `run` mode takes two file descriptors that indicate the channels to
use to communicate with the Perl side. The protocol is explained in
GuestProcess itself and consists in passing JSON messages.

> LEO: The `run` mode should probably accept more resource-specific arguments.
> I'm thinking of JAVA which often requires arguments like -Xmx. I don't
> know where those arguments should be stored. A third column in the
> resource description ?

# Guidelines

## For object-oriented languages

For object-oriented programming languages, the implementation must export a
`BaseRunnable` class that users can inherit from to override the common
eHive methods (`fetch_input()`, `run()`, and `write_output()`, as well as
`pre_cleanup()` and `post_cleanup()`).

BaseRunnable must expose the following attributes:
* `input_id` so that the runnable can dataflow jobs with the same parameters
  as itself
* `retry_count`: the number of times this job has already been tried.
* `autoflow`: defaults to True: False means that the job will not a
  dataflow on branch #1 upon success
* `lethal_for_worker`: defaults to False. True means that the error may
  have contaminated the worker itself, which should bury itself
* `transient_error`: defaults to True. False means that the next error
  can not magically disappear at the next run
* `debug`: an unsigned integer indicating the logging level

`input_id`, `retry_count` and `debug` are seeded by GuestProcess
and should not be editable by the runnable

> * In Compara, `input_id` is only used to create jobs on branches other than
>   #1 with the same parameters as the current job. Perhaps the first
>   argument of `dataflow_output_ids` should be interpreted as follows:
>   undef means that we carry the current job's `input_id`, and a hash
>   (potentially {}) means that we define the `input_id` of the new job.
>   This way, jobs don't need to access their own `input_id`, which could
>   be anyway wrong as it doesn't contain the overriden parameters from
>   accu
> * As you've said, `lethal_for_worker` is trickier for respecializable
>   workers. Probably the solution is to implement a smarter method to
>   report error about (1) the current run, (2) the current job, (3) the
>   current role, (4) the current worker, (5) the current analysis, or (6)
>   the whole pipeline. This method could be merged with `transient_error`
> * `debug` can be freely interpreted. Some runnables test whether it is
>   non-0, some that it is > 0, > 1, etc. We could normalize its usage with
>   pre-defined debug levels (see `warning()` below)

BaseRunnable must also expose the following methods:
* `warning(message, [True|False])`
  to store a message (error or warning) in the database
* `dataflow_output_ids(output_ids, branch_name_or_code)`
  to flow some data on a given branch (to an analysis, a table, etc)
* `worker_temp_directory`
  to get the directory of the worker
* `param(param_name, [new_value])`
  to get/set a parameter
* `param_exists(param_name)`
  returns True if there is a parameter with that name (without attempting
  the substitution)
* `param_is_defined(param_name)`
  returns True if there is a parameter with that name that can be
  successfully substituted
* `param_required(param_name)`
  similar to `param()` but raises an error if the parameter doesn't exist
  or if the substitution fails

>NB: The API for parameters is explained further down this document.

> * Having a single `warning()` method with a `is_error` parameter is
>   not very intuitive and probably too close to the way the message is
>   stored in the database. Perhaps there should be both `warning(message)`
>   and `error(message)` ? Are all the errors fatal ? If yes, `error()`
>   would duplicate `throw()` ? Common libraries about message-logging
>   usually have a second argument that is a log-level: debug, info, warning,
>   error, and critical. We could have the same here (cf the debug flag
>   above).
>   BTW, in Python, I have defined two exceptions that
>   people can use to terminate the job earlier (`CompleteEarlyException`
>   and `JobFailedException`). The latter replaces the need for a specific
>   `throw(message)`
> * `dataflow_output_ids`: should we simply rename it to `dataflow()` ?
>   Also, does the name `branch_name_or_code` refer to the first
>   implementation of semapthores ? I think it would be clearer as
>   `branch_number` if possible. Secondly, the Perl method returns the list
>   of the dbIDs of the new jobs. I think we can hide the database stuff from
>   the other languages, and hence not return the dbIDs, but instead the
>   number of successful dataflows ?
> * `param` as both a getter and a setter: I would find it cleaner to have
>   the two modes in different methods, like `get_param(param_name)` and
>   `set_param(param_name, new_value)`. Also, I haven't included the third mode
>   of Perl's `param`: without any arguments: it returns a hash, doens't it ?
>   It could be cleaner with a third method: `param_list()` or
>   `all_params()` that returns a list of all the parameter names
>   (substituted *and* not substituted) ?
> * `param_exists` and `param_is_defined`: I think the Perl implementations
>   are buggy for some edge cases, I can have a look at it once we agree on
>   the API. Is it worth having both methods ? Is there an interest in jobs
>   detecting the parameters that have an entry but cannot be substituted ?
>   To be useful, we would need to expose a way of reporting which
>   parameters are missing and preventing the substitution. So perhaps we
>   could only have one method with the behaviour of `param_is_defined` ?


## For procedural languages

The implementation for procedural languages must basically expose the same
methods as the OOP-one but in the global namespace.

# Parameter-substitution mechanism

TODO: explain the param syntax


# Completeness of each implementation

Currently, only *python3* fully implements this API. It is to be noted that
some aspects of the API might be difficult -or impossible- to implement (like
`#expr()expr#` on pre-compiled languages). It is thus allowed not to implement
the expr syntax.

Languages that could be implemented:
* C
* C++
* JAVA
* GO
* Ruby

Note that the difficulty of the implementation depends on the language's
API to manipulate sub-strings and parse / write JSON.

