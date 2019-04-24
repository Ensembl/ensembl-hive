Dataflow targets
================

Analysis
--------

In eHive, a Job can create another Job via a Dataflow event by wiring the branch to another Analysis.

Dataflow to one Analysis
~~~~~~~~~~~~~~~~~~~~~~~~

To direct dataflow events to seed a Job for another Analysis, simply name the target Analysis after the ``=>``.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },


Dataflow to multiple Analyses
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A single branch can be connected to seed Jobs for multiple Analyses. When a dataflow
event happens, it will create a Job for each Analysis.

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


Multiple dataflows to the same Analysis
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Reciprocally, an Analysis can be the target of several branches coming
from the same Analysis.
Here, Jobs are created in Beta whenever there is an event on branch #2, in Gamma
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

A Job can store data in a table via the dataflow mechanism, without the need to use raw SQL.

Dataflow to one table
~~~~~~~~~~~~~~~~~~~~~

To insert data passed in a dataflow event into a table, set the target after the ``=>``
to a URL that contains the ``table_name`` key. URLs can be *degenerate*, i.e. skipping the part before
the question mark (like below) or *completely defined*, i.e. starting with ``driver://user@host/database_name``.
Degenerate urls will default to the eHive database.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ '?table_name=Results_1' ],
        },
    },

The parameters passed along with the dataflow event will determine how data is inserted into the table. Parameter
values will be inserted as a row, in columns corresponding to the parameter names. For example, if the dataflow
event on branch #1 has parameters foo = 42 and bar = "hello, world", then the above example would work like
the following SQL:

.. code-block:: sql

    INSERT INTO Results_1 (foo, bar)
    VALUES (42, "hello, world");



Dataflow to multiple tables
~~~~~~~~~~~~~~~~~~~~~~~~~~~

A branch can be connected to multiple tables. When a dataflow
event happens, it will create a row in each of them.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ '?table_name=Results_1', '?table_name=Results_2' ],
        },
    },


Multiple dataflows to tables and Analyses
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

An Analysis can flow data to multiple targets, with Analysis and table types being freely mixed.

Rows inserted by table-dataflows are usually not linked to the emitting job_id.
In the example below, a row from the table Results_1 will typically not have information
about the Analysis (Job) that generated it.
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

The last type of dataflow target is the "Accumulator". It is a way of passing data from fan Jobs
to their funnel.

Single Accumulator
~~~~~~~~~~~~~~~~~~

An Accumulator is defined with a special URL that contains the ``accu_name`` key. There are five types
of Accumulators (scalar, pile, multiset, array and hash), all described in :doc:`accumulators`.

Accumulators can *only* be connected to *fan* Analyses of a semaphore group. All the data flown into them
is *accumulated* for the *funnel* to consume after it is released.

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


Multiple Accumulators and semaphore propagation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

During the semaphore propagation, more Jobs are added to the current semaphore-group
in order to block the current funnel. Similarly a funnel may receive data from multiple
Accumulators (possibly fed by different Analyses) of a semaphore-group.

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


Conditional dataflows
=====================

eHive provides a mechanism to filter dataflow events. It allows mapping a
given branch number to some targets on certain conditions.

The filtering happens based on the values of the parameters. It uses a
`WHEN-ELSE` syntax. It is similar to traditional `IF-THEN` conditions but
with some important differences:

#. `WHEN` happens when a condition is true.
#. There can be multiple `WHEN` cases, and more than one `WHEN` can flow
   (as long as they are true).
#. `ELSE` is the catch-all if none of the `WHEN` cases are true.

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           '2->A' => WHEN(
                        '#a# > 3' => [ 'Beta' ],
                        '#a# > 5' => [ 'Gamma' ],
                        ELSE         [ 'Delta' ],
                     ),
           'A->1' => [ 'Epsilon' ],
        },
    },
    {   -logic_name => 'Beta',
    },
    {   -logic_name => 'Gamma',
    },
    {   -logic_name => 'Delta',
    },
    {   -logic_name => 'Epsilon',
    }


This examples shows how single and multiple `WHEN` cases are handled,
together with their `ELSE` clause.

+----------------+----------------+
| Value of ``a`` | Active targets |
+================+================+
| 2              | Delta          |
+----------------+----------------+
| 4              | Beta           |
+----------------+----------------+
| 6              | Beta, Gamma    |
+----------------+----------------+


