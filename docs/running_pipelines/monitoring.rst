.. eHive guide to running pipelines: monitoring your pipeline, and identifying trouble

Tools for monitoring your pipeline
==================================

Generating a pipeline's flow diagram
------------------------------------

As soon as the pipeline database is ready you can store its visual flow
diagram in an image file. This diagram is a much better tool for
understanding what is going on in the pipeline. Run the following
command to produce it:

::

            generate_graph.pl -url sqlite:///my_pipeline_database -out my_diagram.png


You only have to choose the format (gif, jpg, png, svg, etc) by setting
the output file extension.

|example\_diagram|

Legend:

-  The rounded nodes on the flow diagram represent Analyses (classes of
   jobs).
-  The white rectangular nodes represent Tables that hold user data.
-  The blue solid arrows are called "dataflow rules". They either
   generate new jobs (if they point to an Analysis node) or store data
   (if they point at a Table node).
-  The red solid arrows with T-heads are "analysis control rules". They
   block the pointed-at Analysis until all the jobs of the pointing
   Analysis are done.
-  Light-blue shadows behind some analyses stand for "semaphore rules".
   Together with red and green dashed lines they represent our main job
   control mechanism that will be described elsewhere.

Each flow diagram thus generated is a momentary snapshot of the pipeline
state, and these snapshots will be changing as the pipeline runs. One of
the things changing will be the colour of the Analysis nodes. The
default colour legend is as follows:

-  :hivestatus:`<EMPTY>[ EMPTY ]` : the Analysis never had any jobs to do. Since pipelines
   are dynamic it may be ok for some Analyses to stay EMPTY until the
   very end.
-  :hivestatus:`<DONE>[ DONE ]` : all jobs of the Analysis are DONE. Since pipelines are
   dynamic, it may be a temporary state, until new jobs are added.
-  :hivestatus:`<READY>[ READY ]` : some jobs are READY to be run, but nothing is running
   at the moment.
-  :hivestatus:`<INPROGRESS>[ IN PROGRESS ]` : some jobs of the Analysis are being processed at
   the moment of the snapshot.
-  :hivestatus:`<BLOCKED>[ BLOCKED ]` : none of the jobs of this Analysis can be run at the
   moment because of job dependency rules.
-  :hivestatus:`<FAILED>[ FAILED ]` : the number of FAILED jobs in this Analysis has gone
   over a threshold (which is 0 by default). By default **beekeeper.pl**
   will exit if it encounters a FAILED analysis.

Another thing that will be changing from snapshot to snapshot is the job
"breakout" formula displayed under the name of the Analysis. It shows
how many jobs are in which state and the total number of jobs. Separate
parts of this formula are similarly colour-coded:

-  :hivestatus:`<SEMAPHORED> __s (SEMAPHORED)` - individually blocked jobs
-  :hivestatus:`<READY> __r (READY)` - jobs that are ready to be claimed by Workers
-  :hivestatus:`<INPROGRESS> __i (IN PROGRESS)` - jobs that are currently being processed
   by Workers
-  :hivestatus:`<DONE> __d (DONE)` - successfully completed jobs
-  :hivestatus:`<FAILED> __f (FAILED)` - unsuccessfully completed jobs

Actually, you don't even need to generate a pipeline database to see its
diagram, as the diagram can be generated directly from the PipeConfig
file:

::

            generate_graph.pl -pipeconfig Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -out my_diagram2.png


Such a "standalone" diagram may look slightly different (analysis\_ids
will be missing).

PLEASE NOTE: A very friendly **guiHive** web interface can periodically
regenerate the pipeline flow diagram for you, so you can now monitor
(and to a certain extent control) your pipeline from a web browser.



Monitoring the progress via a direct database session
-----------------------------------------------------

In addition to monitoring the visual flow diagram (that could be
generated manually using
`**generate\_graph.pl** <scripts/generate_graph.html>`__ or via the
**guiHive** web interface) you can also connect to the pipeline database
directly and issue SQL commands. To avoid typing in all the connection
details (syntax is different depending on the particular database engine
used) you can use a bespoke `**db\_cmd.pl** <scripts/db_cmd.html>`__
script that takes the eHive database URL and performs the connection for
you:


::

    db_cmd.pl -url $EHIVE_URL


Once connected, you can list the tables and views with ``SHOW TABLES;``.
The default set of tables should look something like:

::

    +----------------------------+
    | Tables_in_hive_pipeline_db |
    +----------------------------+
    | accu                       |
    | analysis_base              |
    | analysis_ctrl_rule         |
    | analysis_data              |
    | analysis_stats             |
    | analysis_stats_monitor     |
    | dataflow_rule              |
    | hive_meta                  |
    | job                        |
    | job_file                   |
    | log_message                |
    | msg                        |
    | pipeline_wide_parameters   |
    | progress                   |
    | resource_class             |
    | resource_description       |
    | resource_usage_stats       |
    | role                       |
    | worker                     |
    | worker_resource_usage      |
    +----------------------------+


Some of these tables, such as ``analysis_base``, ``job`` and
``resource_class`` may be populated with entries depending on what is in
you configuration file. At the very least you should expect to have your
analyses in ``analysis_base``. Some tables such as ``log_message`` will
only get populated while the pipeline is running (for example
``log_message`` will get an entry when a job exceeds the memory limit
and dies).

Please refer to the eHive schema (see `eHive schema
diagram <hive_schema.png>`__ and `eHive schema
description <hive_schema.html>`__) to find out how those tables are
related.

In addition to the tables, there is a "progress" view from which you can
select and see how your jobs are doing:

::

            SELECT * from progress;


If you see jobs in 'FAILED' state or jobs with retry\_count>0 (which
means they have failed at least once and had to be retried), you may
need to look at the "msg" view in order to find out the reason for the
failures:

::

            SELECT * FROM msg WHERE job_id=1234;    # a specific job


or

::

            SELECT * FROM msg WHERE analysis_id=15; # jobs of a specific analysis


or

::

            SELECT * FROM msg;  # show me all messages


Some of the messages indicate temporary errors (such as temporary lack
of connectivity with a database or file), but some others may be
critical (wrong path to a binary) that will eventually make all jobs of
an analysis fail. If the "is\_error" flag of a message is false, it may
be just a diagnostic message which is not critical.


Monitoring the progress via guiHive
-----------------------------------

guiHive is a web-interface to a eHive database that allows to monitor
the state of the pipeline. It displays flow diagrams of all the steps in
the pipeline and their relationship to one another. In addition it
colours analyses based on completion and each analysis has a progress
circle which indicates the number of complete, running and failed jobs.
guiHive also offers the ability to directly modify analyses, for example
you can change the resource class used by the analysis directly through
guiHive.

guiHive is already installed at the
`Sanger <http://guihive.internal.sanger.ac.uk:8080/>`__ and at the
`EBI <http://guihive.ebi.ac.uk:8080/>`__ (both for internal use only),
but can also be installed locally. Instructions for this are on
`GitHub <https://github.com/Ensembl/guiHive>`__


.. |example_diagram| image:: ../LongMult_diagram.png


