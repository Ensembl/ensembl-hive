
> This document explains how to add support for new languages in eHive

# Introduction

eHive provide a generic interface to interact with runnables written in
languages other than Perl. This is mainly a communication protocol based on
JSON, and managed by the Perl module ``Bio::EnsEMBL::Hive::ForeignProcess``.

Support must come in two parts:
* a wrapper that ForeignProcess will launch, which will in turn run the
  user's Runnable
* a port of eHive's Runnable API to the new language, which people can use
  in their Runnables

This documents explains both aspects in details.

# Interface for wrappers

> In this section, ``${language}`` is the name of the programming
> language, ``${module_name}`` is the name of the user's runnable

There must be an executable under ``ensembl-hive/wrappers/${language}/``
that is registered in ``ensembl-hive/modules/Bio/EnsEMBL/Hive/ForeignProcess.pm``

> LEO: should the wrapper always be called "wrapper" (without an extension
> ?). We could then simply skip the "registration" process.

It works in two modes:
* ``${executable} ${module_name} compile``
* ``${executable} ${module_name} run ${fd_in} ${fd_out}``

The ``compile`` mode is used to check that the Runnable can be loaded and is a
valid eHive Runnable. The return code must be 0 upon success, or 1 otherwise.

The ``run`` mode takes two file descriptors that indicate the channels to
use to communicate with the Perl side. The protocol is explained in
ForeignProcess itself and consists in passing JSON messages.

# Guidelines

## For object-oriented languages

For object-oriented programming languages, the implementation must export a
``BaseRunnable`` class that users can inherit from to override the common
eHive methods (``fetch_input()``, ``run()``, and ``write_output()``, as well as
``pre_cleanup()`` and ``post_cleanup()``).

BaseRunnable must also expose the following methods:
* ``warning(message, [True|False])``
  to store a message (error or warning) in the database
* ``dataflow(output_ids, branch_name_or_code)``
  to flow some data on a given branch (to an analysis, a table, etc)
* ``worker_temp_directory``
  to get the directory of the worker
* ``param(param_name, [new_value])``
  to get/set a parameter
* ``param_required(param_name)``
  similar to ``param()`` but raises an error if the parameter doesn't exist
* ``param_exists(param_name)``
  returns True if the parameter is definable
* ``param_is_defined(param_name)``
  returns True if the parameter is defined and non-null

>NB: The APi for parameters is explained below.

> LEO: Here are questions about the API:
> * ``warning()`` with ``is_error``: should there be both ``warning(message)``
>   and ``error(message)`` ? In Python, I have defined two exceptions that
>   people can use to terminate the job earlier (``CompleteEarlyException``
>   and ``JobFailedException``). The latter replaces the need for a specific
>   ``throw(message)``
> * ``dataflow``: Does the name ``branch_name_or_code`` refer to the first
>   implementation of semapthores ? I think it would be clearer as
>   ``branch_number`` if possible. Secondly, the Perl method returns the list
>   of the dbIDs of the new jobs. I think we can hide the database stuff from
>   the other languages, and hence not return the dbIDs, but instead the
>   number of successful dataflows ?
> * ``param`` as both a getter and a setter: I would find it cleaner to have
>   the two modes in different methods, like ``get_param(param_name)`` and
>   ``set_param(param_name, new_value)``
> * ``param_exists``: there is an entry with that key in either
>   ``_param_hash`` or ``_unsubstituted_param_hash``. I don't try to
>   perform any substitutions
> * ``param_required``: raw call to an internal method ``get_param`` that
>   may raise several kinds of exceptions, especially a KeyError if the
>   parameter is not found in the hash
> * ``param``: also calls ``get_param`` but catches the KeyError exception
>   and print a warning + returns None in this case. The two other exceptions:
>   an infinite loop while substituting, and the user trying to substitute
>   a non-standard structure (not a list / hash) are not caught
> * ``param_is_defined``: returns False if there is no entry with that key
>   in ``_param_hash`` and ``_unsubstituted_param_hash``. If there is,
>   calls ``get_param``. KeyError is caught and mapped to False. Other
>   exceptions are not caught. If no exceptions are raised, returns True if
>   the value of the parameter is not None
>   In the history of Perl, we first introduced ``param_is_defined`` and
>   then ``param_required`` because the latter was a better description of
>   the test we really wanted to achieve. Should we only expose one of them ?


## For procedural languages

The implementation for procedural languages must basically expose the same
methods as the OOP-one but in the global namespace.

# Parameter-substitution mechanism

TODO: explain the param syntax


# Refactor everything below

# How-to add new languages

Two modules have to be implemented to extend eHive to another language:
* Gestion of parameters (the Param interface)
* Gestion of the process' and job's life cycles

This probably requires:
* The ability to manipulate sub-strings
* an equivalent of ``eval()`` to evaluate ``#expr()expr#`` expressions
* a JSON library to communicate with eHive's ForeignProcess


# Future plans

* Extend the "run" interface to add resource-class parameters (like
  maximum memory usage for Java programs)
* Force the wrappers to be called with the same name, so that languages
  don't have to be registered in ForeignProcess ?

