.. eHive guide to running pipelines: running a pipeline, running jobs

Running a pipeline and running jobs
===================================

.. index:: Pipeconfig

To start a pipeline, first find a PipeConfig and init the pipeline


Seeding jobs into the pipeline database
---------------------------------------

Pipeline database contains a dynamic collection of jobs (tasks) to be
done. The jobs can be added to the "blackboard" either by the user (we
call this process "seeding") or dynamically, by already running jobs.
When a database is created using
`**init\_pipeline.pl** <scripts/init_pipeline.html>`__ it may or may not
be already seeded, depending on the PipeConfig file (you can always make
sure whether it has been automatically seeded by looking at the flow
diagram). If the pipeline needs seeding, this is done by running
`**seed\_pipeline.pl** <scripts/seed_pipeline.html>`__ script, by
providing both the Analysis to be seeded and the parameters of the job
being created:

::

            seed_pipeline.pl -url sqlite:///my_pipeline_database -logic_name "analysis_name" -input_id '{ "paramX" => "valueX", "paramY" => "valueY" }'


It only makes sense to seed certain analyses, typically they are the
ones that do not have any incoming dataflow on the flow diagram.

