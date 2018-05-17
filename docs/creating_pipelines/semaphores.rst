Semaphores and other tools to sequence Job execution
====================================================

eHive has three main ways to control the order in which
Analyses are executed (more precisely, the order in which Jobs for
Analyses are executed). The first is the seeding mechanism that we
have already seen. Simply, while a Job runs, it creates events, and
these events can be wired to create more Jobs:

.. hive_diagram::

    {   -logic_name => 'Alpha',
        -flow_into  => {
           1 => [ 'Beta' ],
        },
    },
    {   -logic_name => 'Beta',
    },

This is often sufficient for simple workflows, but lacks the power and
flexibility to handle more complex situations - such as processing the
output of several independent Jobs running in parallel. To provide
this power and flexibility, eHive implements a "Semaphore" system
(sometimes called "factory, fan, and funnel" or "box and
funnel"). Additionally, a "wait-for" directive is available to be part
of an Analysis definition. This stops all Jobs for that Analysis from
running while some other Analysis has incomplete Jobs. "Wait-for" is
an older feature of eHive and is not generally recommended, but it may
still be seen in older workflows, or may be applicable in some rare
situations.

.. _semaphores-detail:

Semaphores
----------

A Semaphore blocks one or more Jobs from starting until all of the
Jobs in a defined set are :hivestatus:`<DONE>[DONE]` (or
[PASSED_ON]). Semaphores exist in the context of a Semaphore Group,
which has three fundamental components:

  - A blocked Job (or Jobs) waiting for the Semaphore to be released. In eHive terminology, this called the "funnel" or "funnel Job(s)".

  - A group of Jobs the Semaphored (funnel) Job(s) waits for. In eHive terminology, this group is called the "fan" (or sometimes also called the "box," because eHive's graphical display tools identify the fan by drawing a shaded box around the appropriate Analyses or Jobs).

  - A single Job that seeds the funnel and fan Jobs during its execution. In eHive terminology, this is called the "factory".

.. hive_diagram::

    {   -logic_name => 'Factory',
        -flow_into  => {
           '2->A' => [ 'Fan' ],
           'A->1' => [ 'Funnel' ],
        },
    },
    {   -logic_name => 'Fan',
    },
    {   -logic_name => 'Funnel',
    },

Creating a fan-funnel relationship is a matter of wiring dataflow
events from the factory Analysis in that Analysis' flow-into block. To
indicate that Jobs being seeded should be part of a fan that controls
a semaphore, a single-letter "group identifier" is appended to the
dataflow branch number with an arrow. This is the ``'2->A'`` in the
example above. Likewise, to wire a funnel Analysis to a dataflow
branch, the dataflow branch is prepended by a group identifier. For
example ``'A->1'``. Note that group identifier letters are arbitrary,
and have nothing to do with the logic names of the Analyses in the
group. Also be aware that group identifiers are unique only in the
scope of a single factory Analysis. For example, if a pipeline has a
factory Factory_alpha which seeds a fan using group identifier "A",
this group will be completely independent from a different factory
Factory_beta which also seeds a fan using group identifier "A".

Writing it out in sentences: ``2->A`` means that all the dataflow
events on branch #2 will be grouped together in a group named
"A". ``A->1`` means that the funnel Job resulting from the dataflow
event on branch #1 has to wait for *all* the Jobs in group A before it
can start.

Multiple Analyses in the same fan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A factory can seed multiple Jobs of different Analysis types into the
same fan, by using events with the same or different dataflow branch
numbers:

.. hive_diagram::

    {   -logic_name => 'Factory',
        -flow_into  => {
           '2->A' => [ 'Fan_alpha', 'Fan_beta' ],
           '3->A' => [ 'Fan_delta'  ],
           'A->1' => [ 'Funnel' ],
        },
    },
    {   -logic_name => 'Fan_alpha',
    },
    {   -logic_name => 'Fan_beta',
    },
    {   -logic_name => 'Fan_delta',
    },
    {   -logic_name => 'Funnel',
    },

In the above diagram, the Funnel Job seeded by the dataflow event on
branch #1 will have to wait until all Fan_alpha, Fan_beta, and
Fan_delta Jobs are finished.

Multiple fan-funnel groups from the same factory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The same factory can also be wired to create Jobs in multiple fan
groups, by giving each group a distinct identifier:

.. hive_diagram::

   {   -logic_name => 'Factory',
       -flow_into  => {
          '2->A' => [ 'Alpha_fan' ],
          '2->B' => [ 'Beta_fan'  ],
          'A->1' => [ 'Alpha_funnel' ],
          'B->1' => [ 'Beta_funnel' ],
       },
   },
   {   -logic_name => 'Alpha_fan',
   },
   {   -logic_name => 'Beta_fan',
   },
   {   -logic_name => 'Alpha_funnel',
   },
   {   -logic_name => 'Beta_funnel',
   },

Sempahore propagation
~~~~~~~~~~~~~~~~~~~~~

Analyses in a fan can be wired so that their dataflow events generate
Jobs of child Analyses. Jobs from these child Analyses will be part of
the same fan group (and will block the semaphored/funnel Job from
starting) just like Jobs from their parent Analyses:

.. hive_diagram::

    {   -logic_name => 'Factory',
        -flow_into  => {
           '2->A'   => [ 'Fan' ],
           'A->1'   => [ 'Funnel' ],
        },
    },
    {   -logic_name => 'Fan',
        -flow_into  => {
           '1' => ['Fan_child'],
        },
    },
    {   -logic_name => 'Fan_child',
    },
    {   -logic_name => 'Funnel',
    },

Semaphore independent from the autoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A fan-funnel relationship is created the instant a funnel Job is
seeded. At that point in time, the event seeding the funnel "closes
off" the fan, and the Semaphore counter is initialised with the number
of Jobs currently in the fan. After that moment, *if the factory seeds
more Jobs into a fan, these fan Jobs will constitute a new fan group,
which will need to be closed off by a new funnel Job*.

Therefore, it is possible for a factory Job to create several fan-funnel 
groups during its execution. All of these groups execute
independently; the Semaphore controlling a particular funnel Job will
release upon completion of its corresponding fan Jobs.

.. hive_diagram::

   {   -logic_name => 'Factory',
       -flow_into  => {
          '3->A'   => [ 'Fan' ],
          'A->2'   => [ 'Funnel' ],
       },
   },
   {   -logic_name => 'Fan',
   },
   {   -logic_name => 'Funnel',
   },

This also means that, if there are several factory Jobs for the same
factory Analysis, the Semaphore groups for those factories will all be
independent. This is because each factory will be creating a separate
funnel Job (or set of funnel Jobs).

Please see the :ref:`Long-multiplication pipeline walkthrough
<long-multiplication-walkthrough>` for a detailed illustration of how
individual funnel Jobs are independently controlled by different fan
groups.

Mixing all patterns
~~~~~~~~~~~~~~~~~~~

Here, the Semaphore groups created on branches #2 (fan) and #3 (funnel) are automatically expanded
with the Jobs created in the Analysis Delta.

Upon success of the Alpha Job, the *autoflow* will create a Job in Analysis Epsilon which is *not* controlled
by any of the Beta or Gamma Jobs. It can thus start immediately.

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


.. _wait-for-detail:

Wait-for
--------

The ``wait-for`` directive stops Jobs from the specified Analysis from
starting until all Jobs from the designated blocking Analysis have
completed.

.. hive_diagram::

   {   -logic_name => 'Seeding',
       -flow_into  => {
          '1' => [ 'Waiting' ],
          '2' => [ 'Blocking' ],
       },
   },
   {   -logic_name => 'Waiting',
       -wait_for   => 'Blocking',
   },
   {   -logic_name => 'Blocking',
   },

In the above example, the Waiting Job, after being seeded, will not
run until all Blocking Jobs are :hivestatus:`<DONE>[DONE]` or
[PASSED_ON].

Note that "blocking" and "waiting" Analyses do not have to share the same parent:

.. hive_diagram::

   {   -logic_name => 'Alpha',
       -flow_into  => {
          '1' => [ 'Waiting' ],
          '2' => [ 'Beta' ],
       },
   },
   {   -logic_name => 'Waiting',
       -wait_for => 'Blocking',
   },
   {   -logic_name => 'Beta',
       -flow_into  => {
          '2' => [ 'Blocking' ],
       },
   },
   {   -logic_name => 'Blocking',
   },

Although superficially this may seem similar to semaphore groups,
there are a number of important differences:

  - There is no fan-funnel style relationship between blocking and waiting Jobs. If *any* Jobs in the blocking Analysis are incomplete then no waiting Jobs can start.

  - Likewise, if at some moment there are no incomplete Jobs in a blocking Analysis, then Jobs of the waiting Analysis will be able to start. This can happen even if there will subsequently be new Jobs seeded into the blocking Jnalysis.

  - Waiting Jobs will only wait on Analyses specifically referred to in the wait_for directive. If there is a child Analysis that should also block Jobs in a waiting Analysis, then that child Analysis must also be explicitly listed in the wait_for directive.
