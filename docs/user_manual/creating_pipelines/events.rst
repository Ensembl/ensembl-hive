.. ehive creating pipelines guide, a description of events

Events in eHive
===============

Dataflows
---------

eHive is an *event-driven* system whereby agents trigger events that
are immediately reacted upon. The main event is called **Dataflow** and
consists of sending some data somewhere. The destination of a Dataflow
event must be defined in the pipeline graph itself, and is then referred to
by a *branch number* (see :doc:`dataflows`).

Within a Runnable, Dataflow events are performed via the ``$self->dataflow_output_id($data,
$branch_number)`` method.

The payload ``$data`` muts be of one of these types:

- Hash-reference that maps parameter names (strings) to their values.
- Array-reference of hash-references of the above type
- ``undef`` to propagate the job's input_id

The branch number defaults to 1 and can be skipped. Generally speaking, it
has to be an integer.

:doc:`dataflows` explains further how to configure branch numbers within a
pipeline. :doc:`dataflow_targets` lists the possible target types.


Conditional dataflows
---------------------

eHive provides a mechanism to filter Dataflow events. It allows mapping a
given branch number to some targets on certain conditions.

The filtering happens based on the values of the parameters. It uses a
`WHEN-ELSE` syntax. It is similar to traditional `IF-THEN` conditions but
with some important differences:

#. `WHEN` happens when a condition is true.
#. There can be multiple `WHEN` cases, and more than one `WHEN` can flow
   (as long asa they are true).
#. `ELSE` is the catch-all if none of the `WHEN` cases are true

The following examples show how single and multiple `WHEN` cases are handled,
together with their `ELSE` clause.

::

    WHEN('#a# > 3' => ['analysis_b'],
         '#a# > 5' => ['analysis_c'],
         ELSE ['analysis_d'],
    )

+----------------+------------------------+
| Value of ``a`` | Active targets         |
+================+========================+
| 2              | analysis_d             |
+----------------+------------------------+
| 4              | analysis_b             |
+----------------+------------------------+
| 6              | analysis_b, analysis_c |
+----------------+------------------------+


