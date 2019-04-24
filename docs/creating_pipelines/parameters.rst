.. eHive guide to creating pipelines: parameter scope

.. _parameters-overview:

Job parameters
==============


Parameter sources
-----------------

Job parameters come from various places and are all aggregated using the
following precedence rules:

#. Job-specific parameters:

   #. Accumulated parameters.
   #. Job's input_id.
   #. Inherited parameters from previous Jobs, still giving priority to a
      given Job's accumulated parameters over its input_id.
#. Analysis-wide parameters
#. Pipeline-wide parameters
#. Default parameters hard-coded in the Runnable

Jobs can access all their parameters via ``$self->param('param_name')`` regardless of their origin.


.. _parameters-substitution:

Parameter substitution
----------------------

You can manipulate parameters in a sophisticated way within the ``flow-into`` section of a PipeConfig file.
Within this section, you can use hash-sign-based constructs in parameter values to rename or interpolate
other parameters' values.

Full redirection
~~~~~~~~~~~~~~~~

A "full redirection" happens when the value of a parameter ``a`` is
defined as ``#b#``. This means that eHive will return ``b``'s value when
``$self->param('a')`` is called, regardless of ``b``'s type (e.g. a numeric
value, a string, a structure made of hashes and arrays, or even ``undef``).

:Syntax:
    ``-flow_into => {1 => {'target_analysis' => {'a' => '#b#'}}}``


Interpolation
~~~~~~~~~~~~~

Parameter values can also be interpolated like in other languages (Perl,
PHP, etc.). For instance, if the value of a parameter ``a`` is defined as
``value is #b#``, ``b``'s value will be *stringified* and appended to the
string "value is ". This only works well for numeric and string values as
Perl stringifies hashes and arrays to a reference (e.g. ``HASH(0x1760cb8)``).

:Syntax:
    ``-flow_into => {1 => {'target_analysis' => {'a' => 'value is #b#'}}}``


Arbitrary expressions
~~~~~~~~~~~~~~~~~~~~~

Arbitrary Perl expressions can also be used via the ``#expr()expr#``
construct. Any valid Perl expressions can be put within the parentheses;
parameters are inserted into the expression by enclosing them with hash marks
(``#b#``, ``#c#``, etc.)

For example, to add 1 to the value in parameter 'alpha', define
``'alpha_plus_one' => '#expr( #alpha#+1 )expr#'``. The next
Job will then see a parameter ``alpha_plus_one`` which will have
a value one greater than the value of ``alpha``.

If the parameter holds a data structure (arrayref or hashref), you can
dereference it with curly-braces as in standard Perl. You can use these
methods from `List::Util <https://perldoc.perl.org/List/Util.html>`_:
first, min, max, minstr, maxstr, reduce, sum, shuffle.

For example, ``'array_max' => '#expr( max @{#array#} )expr#'`` will
dereference ``$self->param('array')`` and call ``max`` on it.


Substitution chaining
~~~~~~~~~~~~~~~~~~~~~

Substitutions can involve more than two parameters in a chain, e.g. ``a``
requires ``b``, which requires ``c``, which requires ``d``, etc., each of
the substitutions being one of the patterns described above.

In the example below, the ``comp_size`` parameter is a hash associating filenames to their size once compressed.
The ``text`` parameter is a message composed of the minimum and maximum compressed sizes.

::

    'min_comp_size' => '#expr(min values %{#comp_size#})expr#',
    'max_comp_size' => '#expr(max values %{#comp_size#})expr#',
    'text' => 'compressed sizes between #min_comp_size# and #max_comp_size#',


Dataflow templates
------------------

"Templates" are a way of setting the input_id of the newly created Jobs
differently from what has been passed in the dataflow with ``dataflow_output_id()``.
For instance, you may want to connect a Runnable "R" that flows
two parameters named ``name`` and ``dbID`` into an Analysis that expects
``species_name`` and ``species_id``. We need to let eHive know about the
mapping ``{ 'species_name' => '#name#', 'species_id' => '#dbID#' }``. This
mapping can be defined in three places:

#. Pipeline-wide parameters, but only if this doesn't clash with other
   usages of ``species_name`` and ``species_id``.
#. Analysis-wide parameters of *every* downstream Analysis. This can
   obviously be quite tedious.
#. Template on the dataflow coming from the Runnable "R":
   ::

       {   -logic_name => 'R',
           -flow_into  => {
               2 => { 'R_consumer' => { 'species_name' => '#name#', 'species_id' => '#dbID#' } },
           },
       },
       {   -logic_name => 'R_consumer',
       },

This will tell eHive that Jobs created in ``R_consumer`` must have their
input_ids composed of two parameters ``species_name`` and ``species_id``,
whose values respectively are ``#name#`` and ``#dbID#``.

Values in template expressions are evaluated like with
``$self->param('param_name')``, meaning they can undergo complex
substitution patterns. These expressions are evaluated in the context of
the runtime environment of the emitting Job.

Expressions can also be simple "pass-through" definitions, like
``'creation_date' => '#creation_date#'``.


Parameter scope
---------------

Explicit propagation and templates
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

By default, parameters are passed in an *explicit* manner, i.e. they have
to be explicitly listed at one of these two levels:

#. In the code of the emitting Runnable, by listing them in the
   ``dataflow_output_id()`` call,
#. In the pipeline configuration, with templates to dataflow-targets.

A common problem when using *factory* dataflows is that the *fan* Jobs may
need access to some parameters of their factory, but this is not
necessarily granted by the system.
For instance, eHive's JobFactory Runnable emits hashes that do *not* 
include any of its input parameters. In this case, you will need to define a
template to add the extra required parameters.

In the example below, the "parse_file" Analysis expects its Jobs to have
the ``inputfile`` parameter defined. "parse_file" is a JobFactory Analysis
that will read the tab-delimited file, extract the first two columns and
create one dataflow event per row. Each event will carry two parameters, one
named ``species_name`` and the other ``species_id``. These events are wired
to seed Jobs of an Analysis named "species_processor". By default the
latter will *not* know the name of the input-file the data comes from. If
it requires the information, we can use templates to define the input_ids
of its Jobs as 1) the parameters set by the factory and 2) the extra
``inputfile`` parameter - which comes from parse_file's input_id. Note that
with the explicit propagation, you will need to list *all* the parameters
that you want to propagate.

::

     {   -logic_name => 'parse_file',
         -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
         -parameters => {
             'column_names'     => [ 'species_name', 'species_id' ],
         },
         -flow_into  => {
             2 => { 'species_processor' => { 'species_name' => '#species_name#', 'species_id' => '#species_id#', 'inputfile' => '#inputfile#' } },
         },
     },
     {   -logic_name => 'species_processor',
     },


Per-Analysis implicit propagation using *INPUT_PLUS*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

INPUT_PLUS is a template modifier that makes the dataflow automatically
propagate both the dataflow output_id and the emitting Job's parameters.
The Analysis above can be rewritten as:

::

     {   -logic_name => 'parse_file',
         -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
         -parameters => {
             'column_names'     => [ 'species_name', 'species_id' ],
         },
         -flow_into  => {
             2 => { 'species_processor' => INPUT_PLUS() },
         },
     },
     {   -logic_name => 'species_processor',
     },

INPUT_PLUS is specific to a dataflow target, and has to be repeated in
all the Analyses that require it.

It can also be extended to include other templated variables, like
``INPUT_PLUS( { 'species_key' => '#species_name#_#species_id#' } )``

Here is a diagram showing how the parameters are propagated in the absence
/ presence of INPUT_PLUS modifiers.

.. graphviz::

   digraph {
      label="Propagation without INPUT_PLUS"
      A -> B;
      A -> D;
      B -> C;
      B -> E;
      A [color="red", label=<<font color='red'>Job A<br/>Pa<sub>1</sub>,Pa<sub>2</sub></font>>];
      B [color="DodgerBlue", label=<<font color='DodgerBlue'>Job B<br/>Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>>];
      C [label=<Job C<br/>Pc<sub>1</sub>,Pc<sub>2</sub>>];
      D [label=<Job D<br/>Pd<sub>1</sub>>];
      E [label=<Job E<br/>Pe<sub>1</sub>>];
   }

.. graphviz::

   digraph {
      label="Propagation with INPUT_PLUS"
      A -> B [label="INPUT_PLUS"];
      A -> D [label=<<i>no INPUT_PLUS</i>>];
      B -> C [label=<<i>no INPUT_PLUS</i>>];
      B -> E [label="INPUT_PLUS"];
      A [color="red", label=<<font color='red'>Job A<br/>Pa<sub>1</sub>,Pa<sub>2</sub></font>>];
      B [color="DodgerBlue", label=<<font color='DodgerBlue'>Job B<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>>];
      C [label=<Job C<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,Pc<sub>1</sub>,Pc<sub>2</sub>>];
      D [label=<Job D<br/>Pd<sub>1</sub>>];
      E [label=<Job E<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,<font color='DodgerBlue'>Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>,Pe<sub>1</sub>>];
   }

Global implicit propagation
~~~~~~~~~~~~~~~~~~~~~~~~~~~

In this mode, all the Jobs automatically see all the parameters of their
ascendants, without having to define any templates or INPUT_PLUS.
Global implicit propagation is enabled by adding a ``hive_use_param_stack``
``hive_meta`` parameter set to 1, like in the example below:

::

    sub hive_meta_table {
        my ($self) = @_;
        return {
            %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class
            'hive_use_param_stack'  => 1,           # switch on the new param_stack mechanism
        };
    }

The *parse_file* Analysis then becomes:

::

     {   -logic_name => 'parse_file',
         -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
         -parameters => {
             'column_names'     => [ 'species_name', 'species_id' ],
         },
         -flow_into  => {
             2 => [ 'species_processor' ],
         },
     },
     {   -logic_name => 'species_processor',
     },

Reusing the same five Jobs as in the previous section, here is how the
parameters would be propagated when ``hive_use_param_stack`` is switched
on.

.. graphviz::

   digraph {
      A -> B;
      A -> D;
      B -> C;
      B -> E;
      A [color="red", label=<<font color='red'>Job A<br/>Pa<sub>1</sub>,Pa<sub>2</sub></font>>];
      B [color="DodgerBlue", label=<<font color='DodgerBlue'>Job B<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>>];
      C [label=<Job C<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,<font color='DodgerBlue'>Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>,Pc<sub>1</sub>,Pc<sub>2</sub>>];
      D [label=<Job D<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,Pd<sub>1</sub>>];
      E [label=<Job E<br/><font color='red'>Pa<sub>1</sub>,Pa<sub>2</sub></font>,<font color='DodgerBlue'>Pb<sub>1</sub>,Pb<sub>2</sub>,Pb<sub>3</sub></font>,Pe<sub>1</sub>>];
   }

