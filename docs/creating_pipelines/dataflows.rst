.. _dataflows:

Dataflows
+++++++++

Dataflow patterns
=================

.. contents::

Autoflow
--------

"Autoflow" is the default event that happens between consecutive Analyses

Autoflow
~~~~~~~~

Upon success, each Job from Alpha will generate a Dataflow event on branch #1, which is connected to Analysis Beta. This is called
autoflow as events seem to automatically flow from Alpha to Beta.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },


Concise autoflow
~~~~~~~~~~~~~~~~

Same as above, but more concise.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => [ 'Beta' ],
    },
    {   -logic_name => 'Beta',
    },


Compact autoflow
~~~~~~~~~~~~~~~~

Same as above, but even more concise

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => 'Beta'
    },
    {   -logic_name => 'Beta',
    },


Custom, independent, dataflows
------------------------------

The autoflow mechanism only triggers one event, and only upon completion. To create more events, or under different circumstances,
you can use "factory" patterns.

Factory
~~~~~~~

Analysis Alpha triggers zero, one or many dataflow events on branch #2 (this is the convention for non-autoflow events).
In this pattern, Alpha is called the "factory", Beta the "fan".

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },


Factory in parallel of the autoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the above example, nothing was connected to the branch #1 of Analysis Alpha. The default autoflow event
was thus lost. You can in fact have both branches connected.

An Analysis can use multiple branches at the same time and for instance produce a fan of Jobs on branch #2
*and* still a Job on branch #1. Both stream of Jobs (Beta and Gamma) are executed in parallel.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta' ],
           1 => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },


Many factories and an autoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

There are virtually no restrictions on the number of branches that can be used.
However, they have to be identified using integers, preferably positive integers for the sake of
this tutorial, as negative branch numbers have a special meaning (which is
addressed in :ref:`resource-limit-dataflow`).

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta' ],
           3 => [ 'Gamma' ],
           4 => [ 'Delta' ],
           1 => [ 'Epsilon' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },
    {   -logic_name => 'Epsilon',
    },


Events connected to multiple targets
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Events on a single dataflow branch can be connected to multiple targets.

.. hive_diagram::

   {    -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta' , 'Gamma' ],
           1 => [ 'Delta', 'Epsilon' ],
        },
   },
   {   -logic_name => 'Beta',
   },
   {   -logic_name => 'Gamma',
   },
   {   -logic_name => 'Delta',
   },
   {   -logic_name => 'Epsilon',
   },

Dependent dataflows and semaphores
----------------------------------

eHive allows grouping of multiple branch definitions to create Job
dependencies. For more detail, please see the section covering
:ref:`semaphores <semaphores-detail>`. Here is a typical example
of a "factory", "fan", and "funnel" combining to form a "semaphore group".

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta', 'Gamma' ],
           'A->1' => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },

- The ``->`` operator groups the dataflow events together.
- ``2->A`` means that all the dataflow events on branch #2 will be grouped
  together in a group named "A". Note that this name "A" is not related
  to the names of the Analyses, or the names of semaphore groups of other
  Analyses.  Group names are single-letter codes, meaning that eHive allows
  up to 26 groups for each Analysis.
- ``A->1`` means that the Job resulting from the Dataflow event on branch
  #1 (the *autoflow*) has to wait for *all* the Jobs in group A before
  it can start. Delta is called the "funnel" Analysis.

Semaphore propagation
---------------------

Dataflow from Jobs in a fan can be directed to seed additional Jobs. These
seeded Jobs become part of the same fan, controlling the same semaphore and
funnel. In eHive, this process is referred to as "semaphore propagation".

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta' ],
           'A->1' => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Beta',
        -flow_into  => {
            1 => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },

Here, Delta will be blocked until all Beta Jobs have completed. It will
also be blocked until any child Gamma Jobs that may have been seeded by the
Beta Jobs are complete.

Dataflow using special error handling branches
----------------------------------------------

The eHive system implements a limited exception handling mechanism that creates :ref:`special dataflow when Jobs exceed resource limits <resource-limit-dataflow>`. These events are generated on special branch -1 (if a MEMLIMIT error is detected), -2 (if a RUNLIMIT error is detected), or 0 (any other failure, see the detailed description below). Here, if Job Low_mem_Alpha fails due to MEMLIMIT, a High_mem_Alpha Job is seeded. Otherwise, a Beta Job is seeded.

.. hive_diagram::

    {    -logic_name => 'Low_mem_Alpha',
         -flow_into  => {
            -1 => [ 'High_mem_Alpha' ],
             1 => [ 'Beta' ],
         },
    },
    {    -logic_name => 'High_mem_Alpha',
         -flow_into  => {
            1 => [ 'Beta' ],
         },
    },
    {    -logic_name => 'Beta',
    },

.. note::

   In PipeConfig files you can use MEMLIMIT or RUNLIMIT as aliases of -1
   and -2, or even MAIN instead of 1. They will automatically be
   transformed to numbers in the database and on diagrams (e.g. guiHive).

There is a generic event named ANYFAILURE (branch 0) that is triggered when
the Worker disappears:

- because of RUNLIMIT or MEMLIMIT, but these branches are not defined,
- or for other reasons (KILLED_BY_USER, for instance)

.. include:: dataflow_targets.rst
.. include:: dataflow_syntax.rst

