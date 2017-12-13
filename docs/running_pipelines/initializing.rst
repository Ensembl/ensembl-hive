.. eHive guide to running pipelines: initializing a pipeline with init_pipeline.pl

.. _init-pipeline-script:

Initializing pipelines using init_pipeline.pl
=============================================

Before a pipeline can be run, the hive database (or "blackboard") must be created
and populated. This is done using eHive's init_pipeline.pl script.

Basic operation
---------------

Two parameters are required by init_pipeline.pl:

  - The fully qualified Perl classname of the PipeConfig to be initialized.

  - The database to be initialized, typically passed as a url using ``-pipeline_url`` [*]_ . It can also be passed in using ``-host``, ``-dbname``, ``-password``, or it can be specified in the ``$EHIVE_URL`` environment variable.

Example:

  - ``init_pipeline.pl MyProject::PipeConfig::ExamplePipeline_conf -pipeline_url mysql://user:password@my.db.server:4567/my_example_pipeline_db``

When this script is run, it performs the following operations:

  - It creates a new database with the name given.

    - If init_pipeline.pl is called with ``-hive_force_init 1`` it will also remove any database with the same name that may exist - e.g. with a ``DROP DATABASE IF EXISTS`` in MySQL.

  - It creates the table structure, along with foreign keys, views, and stored procedures (if applicable).

When init_pipeline.pl successfully completes, it will print a series of useful
commands for working with the now-instantiated pipeline.

Common issues
-------------

There are a few common sources of problems that may be encountered when running
init_pipeline.pl:

  - During pipeline initialization, all of the Runnables listed in the given pipeconfig will be compiled. If the Runnables cannot be located by Perl, Python, or Java then initialization will fail. Errors in a runnable that prevent compilation, such as syntax errors, will also prevent the pipeline from initializing.

  - If the given database already exists, initialization will fail unless the ``-hive_force_init 1`` option has been given. This protects existing pipeline instances from accidental deletion.

  - If the user does not have sufficient permissions (CREATE, INSERT, and ALTER) in the given database, initialization will fail.

.. [*] Note the name ``-pipeline_url`` differs from ``-url`` used in other scripts.
