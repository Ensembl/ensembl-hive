Semaphores and other tools to sequence job execution
====================================================

There are three main ways in eHive to control the order in which
analyses are executed (more precisely, the order in which jobs for
analyses are executed). The first is the seeding mechanism that we
have already seen. Simply, while a job runs, it creates events, and
these events can be wired to create jobs:

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
output of several independent jobs running in parallel. To provide
this power and flexibility, eHive provides a semaphore system
(sometimes called "factory, fan, and funnel" or "box and
funnel"). Additionally, a "wait-for" directive is available to be part
of an analysis definition. This stops all jobs for that analysis from
running while some other analysis has incomplete jobs. "Wait-for" is
an older feature of eHive and is not generally recommended, but it may
still be seen in older pipelines, or may be applicable in some rare
situations.

.. _semaphores-detail:

Semaphores
----------

A semaphore blocks one or more jobs from starting until all of the
jobs in a defined set are :hivestatus:`<DONE>[DONE]` (or
[PASSED_ON]). Semaphores exist in the context of a semaphore group,
which has three fundamental components:

  - A blocked job (or jobs) waiting for the semaphore to be released. In eHive terminology, this called the "funnel" or "funnel job(s)."

  - A group of jobs the semaphored (funnel) job(s) waits for. In eHive terminology, this group is called the "fan" (or sometimes also called the "box," because eHive's graphical display tools identify the fan by drawing a shaded box around the appropriate analyses or jobs)

  - A single job that seeds the funnel and fan jobs during its execution. In eHive terminology, this is called the "factory."

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
events from the factory analysis in that analysis' flow-into block. To
indicate that jobs being seeded should be part of a fan that controls
a semaphore, a single-letter "group identifier" is appended to the
dataflow branch number with an arrow. This is the ``'2->A'`` in the
example above. Likewise, to wire a funnel analysis to a dataflow
branch, the dataflow branch is prepended by a group identifier. For
example ``'A->1'``. Note that group identifier letters are arbitrary,
and have nothing to do with the logic names of the analyses in the
group. Also be aware that group identifiers are unique only in the
scope of a single factory analysis. For example, if a workflow has a
factory 'Factory_alpha' which seeds a fan using group identifier 'A',
this group will be completely independent from a different factory
'Factory_beta' which also seeds a fan using group identifier 'A'.

Writing it out in sentences: ``2->A`` means that all the dataflow
events on branch #2 will be grouped together in a group
named A. ``A->1`` means that the job resulting from the dataflow event
on branch #1 has to wait for *all* the jobs in group A before it can
start.

Multiple analyses in the same fan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

A factory can seed multiple jobs of different analysis types into the
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

In the above diagram, the 'Funnel' job seeded by the dataflow event on
branch #1 will have to wait until all 'Fan_alpha', 'Fan_beta', and
'Fan_delta' jobs are finished.

Multiple fan-funnel groups from the same factory
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The same factory can also be wired to create jobs in multiple fan
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
jobs of child analyses. Jobs from these child analyses will be part of
the same fan group (and will block the semaphored/funnel job from
starting) just like jobs from their parent analyses:

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

A fan - funnel relationship is created the instant a funnel job is
seeded. At that point in time, the event seeding the funnel "closes
off" the fan, and the semaphore counter is initialized with the number
of jobs currently in the fan. After that moment, *if the factory seeds
more jobs into a fan, these fan jobs will constitute a new fan group,
which will need to be closed off by a new funnel job*.

Therefore, it is possible for a factory job to create several fan -
funnel groups during its execution. All of these groups execute
independently; the semaphore controlling a particular funnel job will
release upon completion of its corresponding fan jobs.

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

This also means that, if there are several factory jobs for the same
factory analysis, the semaphore groups for those factories will all be
independent. This is because each factory will be creating a separate
funnel job (or set of funnel jobs).

Please see the :ref:`Long-multiplication pipeline walkthrough
<long-multiplication-walkthrough>` for a detailed illustration of how
individual funnel jobs are independently controlled by different fan
groups.

.. _wait-for-detail:

Wait-for
--------

The wait-for directive stops all jobs from a particular analysis from
starting until all jobs from a different, specified, analysis have
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

In the above example, the 'Waiting' job, after being seeded, will not
run until all 'Blocking' jobs are :hivestatus:`<DONE>[DONE]` or
[PASSED_ON].

Note that 'blocking' and 'waiting' analyses do not have to share the same parent:

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

  - There is no fan-funnel style relationship between blocking and waiting jobs. If *any* jobs in the blocking analysis are incomplete then no waiting jobs can start.

  - Likewise, if at some moment there are no incomplete jobs in a blocking analysis, then jobs of the waiting analysis will be able to start. This can happen even if there will subsequently be new jobs seeded into the blocking analysis.

  - Waiting jobs will only wait on analyses specifically referred to in the wait_for directive. If there is a child analysis that should also block jobs in a waiting analysis, then that child analysis must also be explicitly listed in the wait_for directive.
