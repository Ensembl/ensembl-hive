Dataflow patterns
=================

.. contents::

Autoflow
--------

*Autoflow* is the default event that happens between consecutive analyses

Autoflow
~~~~~~~~

Upon success, each job from Alpha will generate a Dataflow event on branch #1, which is connected to analysis Beta. This is called
*autoflow* as jobs seem to automatically flow from Alpha to Beta.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },


Autoflow v2
~~~~~~~~~~~

Same as above, but more concise.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => [ 'Beta' ],
    },
    {   -logic_name => 'Beta',
    },


Autoflow v3
~~~~~~~~~~~

Same as above, but even more concise

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => 'Beta'
    },
    {   -logic_name => 'Beta',
    },


Custom, independent, dataflows
------------------------------

The autoflow mechanism only triggers 1 event, and only upon completion. To create more events, or under different circumstances,
you can use *factory* patterns.

Factory
~~~~~~~

Analysis Alpha triggers 0, 1 or many Dataflow events on branch #2 (this is the convention for non-autoflow events).
In this pattern, Alpha is called the *factory*, Beta the *fan*.

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

In the above example, nothing was connected to the branch #1 of analysis Alpha. The default *autoflow* event
was thus lost. You can in fact have both branches connected.

An analysis can use multiple branches at the same time and for instance produce a fan of jobs on branch #2
*and* still a job on branch #1. Both stream of jobs (Beta and Gamma) are executed in parallel.

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
They however have to be integers, preferably positive integers for the sake of
this tutorial as negative branch numbers have a special meaning (which is
addressed in :doc:`events`).

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta' ],
           3 => [ 'Gamma' ],
           4 => [ 'Delta' ],
           5 => [ 'Epsilon' ],
           1 => [ 'Foxtrot' ],
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
    {   -logic_name => 'Foxtrot',
    },


Dependent dataflows and semaphores
----------------------------------

eHive allows to group multiple branch definitions to create job dependencies.

Semaphore blocking the autoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Dataflow events can be grouped with the ``->`` operator.

``2->A`` means that all the Dataflow events on branch #2 have to be grouped together
in a group named **A**. Note that this name **A** is not related to the name of the
analysis. Group names are single-letter codes, meaning that eHive allows up to 26 groups
for each analysis.

``A->1`` means that the job resulting from the Dataflow event on branch #1 (the *autoflow*)
has to wait for *all* the jobs in group **A** before it can start.

This pattern is called a *semaphore*, and Gamma is called the *funnel* analysis.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta' ],
           'A->1' => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },


Semaphore propagation
~~~~~~~~~~~~~~~~~~~~~

Jobs created by a job that is part of a semaphore group are
automatically added to the semaphore group.

In the example below, the job in Gamma (the *funnel*) will have to
wait for all its controlling jobs in Beta to complete, but also all
the jobs these may have created in Delta as well.

This process is called *semaphore propagation*.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta' ],
           'A->1' => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
        -flow_into  => {
           2 => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },


Semaphore independent from the autoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The autoflow event is a convenient way of grouping all the jobs created, but semaphore
groups can be created in arbitrary manners.

Here, the Dataflow events on branch #3 are iteratively grouped together (in a group named **A**)
until a Dataflow event is produced on branch #2. This will create *one* semaphore group.

Then, eHive will keep on grouping the following Dataflow events on branch #3 until there is
another Dataflow event on branch #2, which will create *another* semaphore group.

The process is repeated until exhaustion of all Dataflow events. This requires the analysis A to
emit the events in the right order. There are as many semaphore groups as events on branch #2,
each job created on branch #2 is the *funnel* of 0, 1 or many jobs of the *fan* that is defined
on branch #3.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '3->A' => [ 'Beta' ],
           'A->2' => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },


Mixing all patterns
~~~~~~~~~~~~~~~~~~~

Here, the semaphore groups created on branches #2 (fan) and #3 (funnel) are automatically expanded
with the jobs created in te analysis D.

Upon success of the Alpha job, the *autoflow* will create a job in analysis Epsilon which is *not* controlled
by any of the Beta or Gamma jobs. It can thus start immediately.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '3->A' => [ 'Beta' ],
           'A->2' => [ 'Gamma' ],
           1      => [ 'Epsilon' ],
        },
    },
    {   -logic_name => 'Beta',
        -flow_into  => {
           2 => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },
    {   -logic_name => 'Epsilon',
    },


