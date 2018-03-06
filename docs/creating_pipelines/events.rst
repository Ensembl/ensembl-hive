.. ehive creating pipelines guide, a description of events

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


