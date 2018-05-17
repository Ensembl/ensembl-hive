.. _long-multiplication-walkthrough:

========================================
Long Multiplication pipeline walkthrough
========================================

0.  This is a walkthrough of a simple 3-Analysis example workflow.

    The goal of the workflow is to multiply two long numbers. We pretend
    that it cannot be done in one operation on a single machine. So we
    decide to split the task into subtasks of multiplying the first long
    number by individual digits of the second long number for the sake
    of an example. At the last step the partial products are shifted and
    added together to yield the final product.

    We demonstrate what happens in the pipeline with the help of two
    types of diagrams: Job-level dependency (J-)diagrams and
    Analysis-rule (A-)diagrams:

    .. list-table::
       :header-rows: 0

       * - A **J-diagram** is a directed acyclic graph where nodes
           represent Jobs, Semaphores or Accumulators with edges representing
           relationships and dependencies. Most of these objects are created
           dynamically during the pipeline execution, so here you'll see a
           lot of action - the J-diagram will be growing.

           J-diagrams can be generated at any moment during a pipeline's
           execution by running eHive's :ref:`script-visualize_jobs` script (new
           in version/2.5).
         - An **A-diagram** is a directed graph where most of the nodes
           represent Analyses and edges represent rules. As a whole it
           represents the structure of the pipeline which is normally
           static. The only changing elements will be Job counts and
           Analysis colours.

           A-diagrams can be generated at any moment during a pipeline's
           execution by running eHive's :ref:`script-generate_graph` script.


    The main bulk of this document is a commented series of snapshots
    of both types of diagrams during the execution of the pipeline.
    They can be approximately reproduced by running a sequence of
    commands, similar to these, in a terminal:

    ::

            export PIPELINE_URL=sqlite:///lg4_long_mult.sqlite                                                               # An SQLite file is enough to handle this pipeline

            init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $PIPELINE_URL   # Initialize the pipeline database from a PipeConfig file

            runWorker.pl -url $PIPELINE_URL -job_id $JOB_ID                                                                  # Run a specific Job - this allows you to force your own order of execution. Run a few of these

            beekeeper.pl -url $PIPELINE_URL -analyses_pattern $ANALYSIS_NAME -sync                                           # Force the system to recalculate Job counts and determine states of Analyses

            visualize_jobs.pl -url $PIPELINE_URL -out long_mult_jobs_${STEP_NUMBER}.png                                      # To make a J-diagram snapshot (it is convenient to have synchronised numbering)

            generate_graph.pl -url $PIPELINE_URL -out long_mult_analyses_${STEP_NUMBER}.png                                  # To make an A-diagram snapshot (it is convenient to have synchronised numbering)

--------------


1. This is our pipeline just after the initialisation:

   .. list-table::
      :header-rows: 0

      * - |image0|
        -
        - |image1|
      * - The J-diagram shows a couple of 3d-boxes, they represent
          specific Jobs. Each Job is an individual task that can be run on
          an individual machine. We need at least one initial Job to run a
          pipeline. However that one Job may generate many more as it gets
          executed.

          In this example we have two initial Jobs. They were created
          automatically during the pipeline's initialization process. These
          two initial Jobs will generate two independent "streams" of
          execution which will yield their own independent results. Since in
          this particular pipeline we are simply multiplying same two numbers
          in different orders, we expect the final results to be identical.

        -

        - The A-diagram shows how execution of the pipeline is guided by
          Rules. Since the Rules are mostly static, the diagram will also
          be changing very little.

          The main objects on A-diagram are rectangles with rounded corners,
          they represent Analyses. Analyses are types of Jobs (Analyses
          broadly define which code to run, where and how, but miss specific
          parameters which become defined in Jobs). In this pipeline we have
          three types: "take_b_apart", "part_multiply" and "add_together".

          The "take_b_apart" Analysis contains two Jobs, which are in
          READY state (can be checked-out for execution). Our colour for
          READY is green, so both the Analysis and the specific Jobs are
          shown in green.


2. After running the first Job we see a lot of changes on the J-diagram:

   .. list-table::
      :header-rows: 0

      * - |image2|
        -
        - |image3|
      * - Job_1 has finished running and is now in DONE state
          (colour-coded blue). It has generated 6 more Jobs: five in Analysis
          "part_multiply" (splitting its own task into parts) and one in
          Analysis "add_together" (which will recombine the results of the
          former into the final result).

          The newly created "part_multiply" Jobs also control a Semaphore
          which blocks the "add_together" Job which is in SEMAPHORED
          state and cannot be executed yet (grey). The Semaphore is
          essentially a counter that gets decremented each time one of the
          controlling Jobs becomes DONE. It is our primary mechanism for
          synchronisation of control- and dataflow.

        -

        - The topology of A-diagram doesn't normally change, so pay
          attention at more subtle changes of colours and labels:

          - "take_b_apart" Analysis is now yellow (in progress); "1r+1d" stands for "1 READY and 1 DONE".
          - "part_multiply" Analysis is now green (READY); "5r" means "5 READY".
          - "add_together" Analysis is now grey (all Jobs are waiting); "1s" means "1 SEMAPHORED" (or blocked).


3. After running the second Job more Jobs have been added to Analyses "part_multiply" and "add_together".

   .. list-table::
      :header-rows: 0

      * - |image4|
        -
        - |image5|
      * - There is a new Semaphore, a new group of "part_multiply" Jobs to
          control it, and a new "add_together" Job blocked by it.

          Note that the child Jobs sometimes inherit some of their
          parameters from their parent Job ("params from: 1", "params from:
          2").

        -
        - - "take_b_apart" Analysis is completed (no more Jobs to run) and turns blue (DONE)
          - more "part_multiply" Jobs have been generated, all are READY
          - one more "add_together" Job has been generated, and it is also SEMAPHORED

   *Note that the job counts of A-diagram do not provide enough
   resolution to tell which Jobs are semaphored by which. Not even the
   distribution of the Jobs that control Semaphores. This is where
   J-diagram becomes useful.*

4. We finally get to run a Job from the second Analysis.

   .. list-table::
      :header-rows: 0

      * - |image6|
        -
        - |image7|
      * - Once it's done, two things happen:

          - one of the links to the Semaphore turns green and its counter
            gets decremented by 1.
          - some data intended for the Job_3 is sent from Job_4 and
            arrives at an Accumulator.

        -
        -

5. A couple more Jobs get executed with a similar effect

   .. list-table::
      :header-rows: 0

      * - |image8|
        -
        - |image9|
      * - After executing these two Jobs:

          - the Semaphore counter gets decremented by 2 (the number of completed Jobs).
          - the data that they generated gets sent to the corresponding Accumulator.

        -
        -

6. And another couple more Jobs...

   .. list-table::
      :header-rows: 0

      * - |image10|
        -
        - |image11|

7. Finally, one of the Semaphores gets completely unblocked, which results in Job_9 changing into "READY" state.

   .. list-table::
      :header-rows: 0

      * - |image12|
        -
        - |image13|
      * - To recap:

          - Semaphores help us to funnel multiple control sub-threads into
            one thread of execution.
          - Accumulators help to assemble multiple data sub-structures into
            one data structure.

          Their operation is synchronised, so that when a Semaphore opens
          its Accumulators are ready for consumption.
        -
        - - The "add_together" Analysis has turned green, which means it
            finally contains something READY to run
          - the label changed to "1s+1r", which stands for "1 SEMAPHORED
            and 1 READY"


8. Job_9 gets executed.

   .. list-table::
      :header-rows: 0

      * - |image14|
        -
        - |image15|
      * - We can see that the stream of execution starting at Job_2
          finished first. In general, there is no guarantee for the order of
          execution of Jobs that are in READY state.
        -
        - - The results of Job_9 are deposited into the "final_result"
            table.
          - Unlike Accumulators, "final_result" is a pipeline-specific
            non-eHive table, so no link is retained between the Job that
            generated the data and the data in the table.
          - There are no more runnable Jobs in "add_together" Analysis, so
            it turns grey again, with "1s+1d" label for "1 SEMAPHORED and 1
            DONE"

9. The last part_multiply Job gets run...

   .. list-table::
      :header-rows: 0

      * - |image16|
        -
        - |image17|

      * - - Once Job_7 has run the second Semaphore gets unblocked.
          - This makes the second Accumulator ready for consumption and
            Job_3 becomes READY.
        -
        -

10. Job_3 gets executed.

    .. list-table::
       :header-rows: 0

       * - |image18|
         -
         - |image19|
       * - - Finally, all the Jobs are DONE (displayed in blue)
           - The stream of execution starting at Job_1 finished second (it
             could easily be the other way around).
         -
         - The result also goes into the final_result table. We can verify
           that the two results are identical.


.. |image0| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_01.dot
.. |image1| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_01.dot
.. |image2| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_02.dot
.. |image3| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_02.dot
.. |image4| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_03.dot
.. |image5| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_03.dot
.. |image6| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_04.dot
.. |image7| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_04.dot
.. |image8| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_05.dot
.. |image9| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_05.dot
.. |image10| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_06.dot
.. |image11| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_06.dot
.. |image12| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_07.dot
.. |image13| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_07.dot
.. |image14| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_08.dot
.. |image15| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_08.dot
.. |image16| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_09.dot
.. |image17| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_09.dot
.. |image18| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_jobs_10.dot
.. |image19| graphviz:: ../../t/03.scripts/visualize_jobs/long_mult/long_mult_analyses_10.dot
