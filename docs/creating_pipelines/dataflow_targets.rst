Dataflow targets
================

.. contents::

Analysis
--------

In eHive, a job can create another job via a Dataflow event by wiring the branch to another analysis.

Dataflow to one analysis
~~~~~~~~~~~~~~~~~~~~~~~~

This is what we have used in the Dataflow document. Simply name the target analysis after the ``=>``.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },


Dataflow to multiple analyses
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A branch can actually be connected to multiple analyses. When a Dataflow
event happens, it will create a job in each of them.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta', 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },


Multiple dataflows to the same analysis
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Reciprocally, an analysis can be the target of several branches coming
from the same analysis.
Here, jobs are created in Beta whenever there is an event on branch #2, in Gamma
when there is an event on branch #2 or #3, and Delta when there is an event on branch #1.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta', 'Gamma' ],
           3 => [ 'Gamma' ],
           1 => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },


Table
-----

A job can store data in a table via the Dataflow mechanism instead of raw SQL access.

Dataflow to one table
~~~~~~~~~~~~~~~~~~~~~

This is what we have used in the Dataflow document. Simply name the target analysis after the ``=>``
with a URL that contains the ``table_name`` key. URLs can be *degenerate*, i.e. skip the part before
the question mark (like below) or *completely defined*, i.e. start with ``driver://user@host/database_name``.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ '?table_name=Results_1' ],
        },
    },


Dataflow to multiple tables
~~~~~~~~~~~~~~~~~~~~~~~~~~~

A branch can actually be connected to multiple tables. When a Dataflow
event happens, it will create a row in each of them.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ '?table_name=Results_1', '?table_name=Results_2' ],
        },
    },


Multiple dataflows to tables and analyses
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

An analysis can dataflow to multiple targets, both of analysis and table types.

Rows inserted by table-dataflows are usually not linked to the emitting job_id.
In the example below, a row from the table Results_1 will typically not have information
about the analysis (job) that generated it.
This can however be enabled by explicitly adding the job_id to the dataflow payload.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           2 => [ 'Beta', '?table_name=Results_1' ],
           1 => [ 'Gamma' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
        -flow_into  => {
           3 => [ '?table_name=Results_1' ],
        },
    },


Accumulator
-----------

The last type of dataflow-target is called as an *accumulator*. It is a way of passing data from *fan* jobs
to their *funnel*.

Single accumulator
~~~~~~~~~~~~~~~~~~

An accumulator is defined with a special URL that contains the ``accu_name`` key. There are five types
of accumulators (scalar, pile, multiset, array and hash), all described in :doc:`accumulators`.

Accumulators can **only** be connected to *fan* analyses of a semaphore group. All the data flown into them
is *accumulated* and passed on to the *funnel* once the latter is released.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta' ],
           'A->1' => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Beta',
        -flow_into  => {
           1 => [ '?accu_name=pile_accu&accu_input_variable=pile_content&accu_address=[]' ],
        },
    },
    {   -logic_name => 'Delta',
    },


Multiple accumulators and semaphore propagation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

During the semaphore propagation, more jobs are added to the current semaphore-group
in order to block the current funnel. Similarly a funnel may receive data from multiple
accumulators (possibly fed by different analyses) of a semaphore-group.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => [ 'Beta' ],
           'A->1' => [ 'Delta' ],
        },
    },
    {   -logic_name => 'Beta',
        -flow_into  => {
           2 => [ 'Gamma' ],
           1 => [ '?accu_name=pile_accu&accu_input_variable=pile_content&accu_address=[]' ],
        },
    },
    {   -logic_name => 'Gamma',
        -flow_into  => {
           1 => [ '?accu_name=multiset_accu&accu_input_variable=set_content&accu_address={}' ],
        },
    },
    {   -logic_name => 'Delta',
    }


