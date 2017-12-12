=======================
eHive quick start guide
=======================

In this section, we will take you through the basics of setting up one of the example pipelines included with eHive, followed by running that pipeline to completion.

.. contents::

Check that your system is set up to run eHive
=============================================

#. If eHive hasn't been installed on your system, follow the instructions in :ref:`ehive-installation-setup` to obtain the code and set up your environment.

    - In particular, confirm that $PERL5LIB includes the eHive modules directory and that $PATH includes the eHive scripts directory.

    .. warning ::
        Some pipelines may have other dependencies beyond eHive (e.g. the
        Ensembl Core API, BioPerl, etc). Make sure you have installed them
        and configured your environment (PATH and PERL5LIB).
        :ref:`script-init_pipeline` will
        try to compile all the analysis modules, which ensures that most of
        the dependencies are installed, but some others can only be found
        at runtime.

#. You should have a MySQL or PostgreSQL database with CREATE, SELECT, INSERT, and UPDATE privileges available. Alternatively, you should have SQLite available on your system.


Quick overview
==============

Each eHive pipeline is a potentially complex computational process.
Whether it runs locally, on the farm, or on multiple compute resources,
this process is centred around a database where individual jobs of the
pipeline are created, claimed by independent Workers and later recorded as
done or failed.

Running the pipeline involves the following steps:

  #. Using the :ref:`script-init_pipeline` script to create an
       instance pipeline database from a "PipeConfig" file

  #. (optionally) Using the :ref:`script-seed_pipeline` script to
       add jobs to be run

  #. Running the :ref:`script-beekeeper` script that will look
       after the pipeline and maintain a population of Worker processes on
       the compute resource that will take and perform all the jobs of the
       pipeline

  #. (optionally) Monitoring the state of the running pipeline:

       - by using your local guiHive web interface

       - by periodically running the :ref:`script-generate_graph`
         script, which will produce a fresh snapshot of the pipeline
         diagram

       - by connecting to the database using the
         :ref:`script-db_cmd` script and issuing SQL commands


Initialise and run a pipeline
=============================

We'll start by initialising one of the example pipelines included with eHive, the "long-multiplication pipeline." This pipeline is simple to set up and run, with no dependencies on e.g. external data files.

Initialising the pipeline using the init_pipeline.pl script
-----------------------------------------------------------

    - When we initialise a pipeline, we are setting up an eHive database. This database is then used by the beekeeper and by worker processes to coordinate all the work that they need to do. In particular, initialising the pipeline means:

    #. Creating tables in the database. The table schema is the same in any eHive pipeline -- as long as the eHive version is the same. The schema can change between eHive versions (but we provide patch scripts to update your schema should you need to upgrade). The table schema is defined in files in the eHive distribution -- you should not edit or change these files.

    #. Populating some of those tables with data describing the structure of your pipeline, along with initial parameters for running it. It's the data in the tables that defines how a particular pipeline runs, not the structure. This information is loaded from a file known as a PipeConfig file.

        - A PipeConfig file is a Perl module conforming to a particular interface (``Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf``). By convention, these files are given names ending in '_conf.pm'. They must be located someplace that your Perl can find them by class name.

        - In general, the eHive database corresponds to a particular run of a pipeline, whereas the PipeConfig file contains the structure for all runs of a pipeline. To make an analogy with software objects, you can think of the PipeConfig file as something like a class, with the database being an instance of that class.

    - Initialising a pipeline is accomplished by running the ``init_pipeline.pl`` script. This script requires a minimum of two arguments to work:

    #. The classname of the PipeConfig you're initialising

    #. The name of the database to be initialised. This is usually passed in the form of a URL (e.g. ``mysql://username:password@server:port/database_name``, ``postgres://username:password@server:port/database_name``, or ``sqlite:///sqlite_filename``), given via the ``-pipeline_url`` option.

        - There are other options to ``init_pipeline.pl`` that will be covered later in this manual. You can see a list of them with ``init_pipeline.pl -h``. One option you should be aware of is ``-hive_force_init 1``. Normally, if the database already has data in it, then the ``init_pipeline.pl`` command will exit leaving the database untouched, and print a warning message. If ``-hive_force_init 1`` is set, however, then the database will be reinitialised from scratch with any data in it erased. This is a safety feature to prevent inadvertently overwriting a database with potentially many days of work in it, so use this option wisely!

    - Let's run an actual ``init_pipeline.pl`` on the command line. We're going to initialise a hive database for the "long-multiplication pipeline," which is defined in ``Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf``. 

.. code-block:: bash

    # The following command creates a new SQLite database called 'long_mult_hive_db'
    # then sets up the tables and data eHive needs for the long-multiplication pipeline

    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf \
      -pipeline_url 'sqlite:///long_mult_hive_db'

    # Alternatively, you could initialise a MySQL database for this eHive pipeline
    # by running a command like this

    init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf \
      -pipeline_url 'mysql://[username]:[password]@[server]:[port]/long_mult_hive_db'

..

    - After running ``init_pipeline.pl``, you should see a list of useful commands printed to the terminal. If something went wrong, you may see an error message. Some common error messages you might see are:

        - ``ERROR 1007 (HY000) at line 1: Can't create database 'longmult_for_manual'; database exists`` or errors looking like ``Error: near line [line number]: table [table name] already exists`` - means the database you're trying to initialise already exists. Choose a different database name, or run with ``-hive_force_init 1``.

        - ``ERROR 1044 (42000) at line 1: Access denied for user [username] to database`` - means the user given in the url doesn't have enough privileges to create a database and load it with data.

        - ``Can't locate object method "new" via package...`` - usually means the package name in the Perl file doesn't match the filename.

Examining the pipeline you just initialised
-------------------------------------------

Note, this step is optional. Some of these tools may not be available, depending on the software installation in your environment.

    - eHive is distributed with a number of tools that let you examine the structure of a pipeline, along with it's current state and the progress made while working through it. For example, ``tweak_pipeline.pl`` can query pipeline parameters as well as set them while GuiHive allows visualising pipelines in a web browser. Two scripts are included that produce diagrams illustrating a pipeline's structure and the current progress of work through it: ``generate_graph.pl`` and ``visualize_jobs.pl``

    - If a GuiHive server is available and running in your compute environment, open a web browser and connect to that GuiHive server. Enter your pipeline URL into the URL: field and click connect (if you are using a SQLite database, the webserver running GuiHive will need to have access to the filesystem where your SQLite database resides, and you will need to give the full path to the database file: e.g ``sqlite:////home/user/ehive_exploration/long_mult_hive_db``).

    - You can use ``generate_graph.pl`` and ``visualize_jobs.pl`` to generate analysis-level and job-level diagrams of your pipeline (For a more thorough explanation of these diagrams, see the :ref:`long-multiplication-walkthrough`). ``generate_graph.pl`` requires a pipeline url or a pipeconfig classname as an argument. You can specify an output file in a variety of graphics formats, or if no output file is specified, an ascii-art diagram will be generated. ``visualize_jobs.pl`` requires a pipeline url and an output filename to be passed as arguments. Both of these scripts require a working `graphviz <http://www.graphviz.org/>`__ installation. Some usage examples:

.. code-block:: bash

    # generate an analysis diagram for the pipeline in sqlite:///long_mult_hive_db and store it as long_mult_diagram.png
    generate_graph.pl -url sqlite:///long_mult_hive_db -output long_mult_diagram.png

    # generate an analysis diagram for the pipeline defined in
    # Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf and display as ascii-art in the terminal
    generate_graph.pl -pipeconfig Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf

    # generate a job-level diagram for the pipeline in sqlite:///long_mult_hive_db and store it as long_mult_job_diagram.svg
    visualize_jobs.pl -url sqlite:///long_mult_hive_db -output long_mult_job_diagram.svg

Running the pipeline using the beekeeper
----------------------------------------

    - Pipelines are typically run using the ``beekeeper.pl`` script. This is a lightweight script that is designed to run continuously in a loop for as long as your pipeline is running. It checks on the pipeline's current status, creates worker processes as needed to perform the pipeline's actual work, then goes to sleep for a period of time (one minute by default). After each loop, it prints information on the pipeline's current progress and status. As an aside, ``beekeeper.pl`` can perform a number of pipeline maintenance tasks in addition to it's looping function, these are covered elsewhere in the manual.

    - The beekeeper needs to know which hive database stores the pipeline. This is passed with the parameter ``-url`` (e.g. ``-url sqlite:///long_mult_hive_db``)

    - To run the beekeeper in loop mode, where it monitors the pipeline (this is the typical use case mentioned above), pass it the ``-loop`` switch.

        - When looping, you can change the sleep time with the ``-sleep`` flag, passing it a sleep time in minutes (e.g. ``-sleep 0.5`` to shorten the sleep time to 30 seconds)

    - Let's run the beekeeper in loop mode, keeping the default one minute sleep time to provide time to examine the pipeline status messages:

.. code-block:: bash

    # Here is the beekeeper command pointing to the SQLite database initialised in the previous step.
    # Substitute the database url as needed to point to the database you initialised

    beekeeper.pl -url 'sqlite:///long_mult_hive_db' -loop

..

    - You may notice that was one of the "useful commands" listed after running init_pipeline.pl, so you could just copy and paste it to the command line.

    - For this "long multiplication pipeline" the beekeeper should loop three or four times before stopping and returning you to the command prompt. The exact number of loops will depend on your particular system.

    - Many pipelines take a long time to run, so it's usually more convenient to run ``beekeeper.pl`` in some sort of detachable terminal such as `screen <https://www.gnu.org/software/screen/>`__ or `tmux <https://tmux.github.io/>`__ .

    - Last note about Beekeeper: you can see it as a pump. Its task is to
      add new workers to maintain the job flow. If you kill Beekeeper, you
      stop the pump, but the water is still flowing, i.e. the workers are
      not killed but still running. To actually kill the workers, you have
      to use the specific commands of your grid engine (e.g. ``bkill`` for
      Platform LSF).



Making sense of the beekeeper's output
--------------------------------------

    - The beekeeper's output can appear dense and a bit cryptic. However, it is organised into logical sections, with some parts useful for monitoring that your pipeline is OK, with other parts more useful for advanced techniques such as pipeline optimisation.

    - Let's deconstruct the output from a typical beekeeper loop:

        - Each loop begins with a "Beekeeper : loop #N ================= line"

        - There will be a couple of lines starting with "GarbageCollector:" - advanced users may find the information here useful for performance tuning or troubleshooting.

        - There will then be a table showing work that is pending or in progress. This section is the most important to pay attention to in day-to-day eHive operation. These lines show progress being made through the pipeline, and can also provide an early warning sign of trouble. This table has the following columns:

          #. The analysis name and analysis ID number.

          #. The status of the analysis (typically, :hivestatus:`<LOADING>LOADING`, :hivestatus:`<READY>READY`, :hivestatus:`<ALL_CLAIMED>ALL_CLAIMED`, possibly :hivestatus:`<FAILED>FAILED`). Analyses that are done are not shown in this table.

          #. A job summary, showing the number of :hivestatus:`<READY>[r]eady`, :hivestatus:`<SEMAPHORED>[s]emaphored`, :hivestatus:`<INPROGRESS>[i]n-progress`, and :hivestatus:`<DONE>[d]one` jobs in the analysis

          #. Average runtime for jobs in the analysis,

          #. Number of workers working on this analysis

          #. Hive-capacity and analysis-capacity settings for this analysis

          #. Last time the beekeeper performed an internal-bookkeeping synchronization on this analysis.

        - There will then be a summary of progress through the pipeline

        - The next several lines show the beekeeper's plan to create new workers for the pipeline. This can be useful for debugging.

        - Finally, the beekeeper will announce it is going to sleep.

Summary
-------

    - Once eHive is installed, initialising and running pipelines is fairly simple

    #. Initialise the pipeline with init_pipeline.pl

    #. Run beekeeper.pl, pointing it at the pipeline database, until the work is finished.
