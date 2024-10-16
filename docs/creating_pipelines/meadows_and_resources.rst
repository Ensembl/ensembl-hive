.. eHive guide to meadows and resource classes

============================
Meadows and Resource Classes
============================

.. _meadows-overview:

Meadows
=======

For eHive to run a pipeline, it has to be able to create Workers as
actual computational processes with an entry in some sort of process
table. The interface between eHive and the underlying scheduler is
called a "Meadow". There are Meadows available for a number of job
schedulers, and there is a special Meadow called "LOCAL" that allows
Jobs to be run directly on a local machine (e.g. the same machine
where the Beekeeper is running).

eHive autodetects available Meadows when a Pipeline is initialised
with ``init_pipeline.pl``, and when it is run using the Beekeeper. In
order for a Meadow to be available, two conditions must be met:

   - The appropriate Meadow driver must be installed and accessible to Perl (e.g. in your $PERL5LIB).

      - Meadow drivers for SLURM and for the LOCAL Meadow are included with the eHive distribution. Other Meadow drivers are :ref:`available in their own repositories <other-job-schedulers>`.

   - The Beekeeper must be running on a head node that can submit jobs managed by the corresponding job management engine.

An Analysis can be assigned to a particular Meadow using the
optional ``meadow_type`` directive in its :ref:`analysis definition
<pipeline-analyses-section>`. Typically, this is used to force an
Analysis to run in the LOCAL Meadow, although any Meadow name can be
assigned. If a Meadow is assigned using ``meadow_type`` then the
Analysis is constrained to only run in that Meadow.

If no Meadow is specified for an Analysis, it will run in the default
Meadow. This is usually an available non-LOCAL Meadow, or LOCAL if that
is the only Meadow available.

.. _resource-classes-overview:

Resource Classes
================

In eHive, appropriate computational resources are assigned to Analyses
through the use of "Resource Classes". A Resource Class consists of a
"Resource Description" which is identified by a "Resource Class
Name". In early eHive releases, a Resource Class could also be
identified by a "Resource Class ID"; these may still be encountered in
older PipeConfig files.

The Resource Class name can any arbitrary string (whitespace is not
allowed), but it must be unique within the pipeline.

The Resource Description is a data structure (in practice written as a
perl hashref) that links Meadows to a job scheduler submission string
for that Meadow. For example, the following data structure defines a
Resource Class with a Resource Class Name '1Gb_job'. This Resource
Class has a Resource Description for running under the SLURM scheduler,
and another description for running under the LSF scheduler:

.. code-block:: perl

   {
       '1Gb_job' => { 'SLURM' => ' --time=1:00:00  --mem=1000m',
                      'LSF' => '-M 1024  -R"select[mem>1024]  rusage[mem=1024ma]"',
                    },
   }

Resource Classes are defined in the :ref:`resource_class method
<resource-classes-method>` of a PipeConfig file.
