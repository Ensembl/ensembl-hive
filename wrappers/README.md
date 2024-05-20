
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
* `${executable} version`
* `${executable} load ${module_name}`
* `${executable} run ${module_name} ${fd_in} ${fd_out}`

The `version` mode will report the version of the communication protocol
that this wrapper understands.

The `load` mode is used to check that the Runnable can be loaded and is a
valid eHive Runnable. The return code must be 0 upon success, or 1 otherwise.

The `run` mode takes two file descriptors that indicate the channels to
use to communicate with the Perl side. The protocol is explained in
GuestProcess itself and consists in passing JSON messages.

> NB: int he future, We may have to add extra arguments to the `run` mode to pass
> resource-specific parameters.

# Guidelines

## For object-oriented languages

For object-oriented programming languages, the implementation must export a
`BaseRunnable` class that users can inherit from to override the common
eHive methods (`fetch_input()`, `run()`, and `write_output()`, as well as
`pre_cleanup()` and `post_cleanup()`).

BaseRunnable must expose the following attributes via an `input_job` field:
* `input_id` so that the runnable can dataflow jobs with the same parameters
  as itself
* `retry_count`: the number of times this job has already been tried.
* `autoflow`: defaults to True: False means that the job will not a
  dataflow on branch #1 upon success
* `lethal_for_worker`: defaults to False. True means that the error may
  have contaminated the worker itself, which should bury itself
* `transient_error`: defaults to True. False means that the next error
  can not magically disappear at the next run

And these attributes directly:
* `debug`: an unsigned integer indicating the logging level

`input_id`, `retry_count` and `debug` are seeded by GuestProcess
and should not be editable by the runnable

BaseRunnable must also expose the following methods:
* `warning(message, [True|False])`
  to store a message (error or warning) in the database
* `dataflow(output_ids, branch_name_or_code)`
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

>NB: Parameter-substitution is explained further down this document.

## For procedural languages

The implementation for procedural languages must basically expose the same
methods as the OOP-one but in the global namespace.

# Parameter-substitution mechanism

In this section, we look at how a parameter `alpha` is evaluated (and
substituted) in several examples:
* `"#beta#"`: the value of `beta` as is
* `"beta is #beta#"`: text that embeds the stringified version of `beta`
* `"pair(#beta#, #gamma#)"`: same with two parameters
* `"#f:beta#"`: returns `f(beta)` as is (assuming that `f` is a function available in
  eHive's namespace: usually this means one of the global functions /
  builtins of the language)
* `"f(beta) is #f:beta#"`: text that embeds the stringified return-value of
  `f(beta)`
* `"#expr(#beta# + #gamma#)expr#"`: Python expression that is evaluated using
  the true values of `#beta#` and `#gamma#`

# Completeness of each implementation

Currently, only *python3* fully implements this API. It is to be noted that
some aspects of the API might be difficult -or impossible- to implement (like
`#expr()expr#` on pre-compiled languages).

Languages that could be implemented:
* C
* C++
* GO
* Ruby

Note that the difficulty of the implementation depends on the language's
API to manipulate sub-strings and parse / write JSON.

