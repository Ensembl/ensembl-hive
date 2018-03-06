
Dataflow syntax
===============

* At the highest level, the ``-flow_into`` is either a hash
  associating branch tags to targets, or a target directly, in
  which case the branch tag is assumed to be ``1``.
* Branch tags are branch numbers (integers, the same as you would use in
  a Runnable when calling ``dataflow_output_id``) that may be grouped into
  semaphores by adding an arrow and a letter code that identifies the group.
* Essentially, targets are most of the time (local) analysis names, but can
  also be remote analysis names, or accumulator URLs (local or remote).
* Dataflows to these targets can be further controlled in two manners:

  * They can be made conditional using a ``WHEN`` group and a condition. A
    ``WHEN`` group can have as many conditions as you wish, which can
    overlap, and an optional ``ELSE`` clause that acts as a *catch-all*
    (i.e. is activated when no conditions are met).
  * The hash of parameters passed to ``dataflow_output_id`` can be
    transformed before reaching the target with a *template*, which defines
    a new hash of parameters that will be evaluated using eHive's parameter
    substitution mechanism.

Here is a pseudo-BNF definition of the syntax used to model dataflows in
PipeConfig files.

.. code-block:: abnf

  flow-into              = <dataflow-hash> | <target-group>

  dataflow-hash          = "{" <branch-tag> "=>" <target-group> "," * "}"

  branch-tag             = <integer>
                         | <letter> "->" <integer>
                         | <integer> "->" <letter>

  target-group           = <conditional-flow>
                         | <target-names>
                         | <targets-with-template>

  conditional-flow       = "WHEN(" <condition-clause> * <else-clause> ")"

  condition-clause       = <condition> "=>" (<target-names> | <targets-with-template>) ","

  else-clause            = "ELSE" "=>" (<target-names> | <targets-with-template>)

  target-names           = "[" <target-name> * "]"

  targets-with-template  = "{" <target-name> "=>" (<template> | "[" <template> "," * "]" ) "}"

  template               = "undef"
                         | "{" <param-name> "=> "<param-value> "," * "}"

  target-name            = <analysis-name>
                         | <accumulator-url>
                         | <remote-analysis-url>

