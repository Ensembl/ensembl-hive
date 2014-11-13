
# Interface for wrappers

There must be an executable under ``ensembl-hive/wrappers/${language}/`` that is registered
in ``ensembl-hive/modules/Bio/EnsEMBL/Hive/ForeignProcess.pm``

It works in two modes:
* ``${executable} ${module\_name} compile``
* ``${executable} ${module\_name} run ${fd\_in} ${fd\_out}``

The ``compile`` mode is used to check that the module can be loaded and is a
valid eHive Runnable. The return code must be 0 upon success, or 1 otherwise.

The ``run`` mode takes two file descriptors in (that are supposed to be
connected to the parent process).


# How-to add new languages

Two modules have to be implemented to extend eHive to another language:
* Gestion of parameters (the Param interface)
* Gestion of the process' and job's life cycles

This probably requires:
* The ability to manipulate sub-strings
* an equivalent of ``eval()`` to evaluate "#expr()expr#" expressions
* a JSON library to communicate with eHive's ForeignProcess


# Future plans

* Extend the "run" interface to add resource-class parameters (like
  maximum memory usage for Java programs)
* Force the wrappers to be called with the same name, so that languages
  don't have to be registered in ForeignProcess ?

