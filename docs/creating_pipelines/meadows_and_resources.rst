.. eHive guide to meadows and resource classes

============================
Meadows and Resource Classes
============================

.. _meadows-overview:

Meadows
=======

For eHive to run a workflow, it has to be able to create workers as
actual computational processes with an entry in some sort of process
table. The interface between eHive and the underlying scheduler is
called a *Meadow*. There are Meadows available for a number of job
schedulers, and there is a special Meadow called *LOCAL* that allows
jobs to be run directly on a local machine (e.g. the same machine
where the beekeeper is running).

eHive autodetects available Meadows when a workflow is initialized
with init_pipeline.pl, and when it is run using the beekeeper. In
order for a meadow to be available, two conditions must be met:

   - The appropriate Meadow driver must be installed and accessible to Perl (e.g. in your $PERL5LIB).

      - Meadow drivers for LSF and for the LOCAL Meadow are included with the eHive distribution. Other Meadow drivers are :ref:`available in their own repositories <other-job-schedulers>`.

   - The beekeeper must be running on a head node that can submit jobs managed by the corresponding job management engine.

An analysis can be assigned to a particular Meadow using the
optional ``meadow_type`` directive in its :ref:`analysis definition
<pipeline-analyses-section>`. Typically, this is used to force an
analysis to run in the LOCAL Meadow, although any Meadow name can be
assigned. If a Meadow is assigned using ``meadow_type`` then the
analysis is constrained to only run in that Meadow. In particular, it
will not fail to run in the LOCAL Meadow if LOCAL is the only Meadow
available.

If no Meadow is specified for an analysis, it will run in the default
Meadow.

.. _resource-classes-overview:

Resource classes
================

In eHive, appropriate computational resources are assigned to analyses
through the use of resource classes. A resource class consists of a
*resource description* which is identified by a *resource class
name*. In early eHive releases, a resource class could also be
identified by a resource class ID; these may still be encountered in
older workflows.

The resource class name is any arbitrary string (whitespace is not
allowed), but it must be unique within the workflow.

The resource description is a data structure (in practice written as a
perl hashref) that links Meadows to a job scheduler submission string
for that Meadow. For example, the following data structure defines a
resource class with a resource class name '1Gb_job'. This resource
class has a resource description for running under the LSF scheduler,
and another description for running under the SGE scheduler:

.. code-block:: perl

   {
       '1Gb_job' => { 'LSF' => '-M 1024  -R"select[mem>1024]  rusage[mem=1024ma]"',
                      'SGE' => '-l h_vmem=1G',
                    },
   }

Resource classes are defined in the :ref:`resource_class method
<resource-classes-method>` of a PipeConfig file.
