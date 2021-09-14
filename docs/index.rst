.. ehive_user_manual documentation master file, created by
   sphinx-quickstart on Thu Dec 15 12:59:35 2016.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

.. Have a look at https://raw.githubusercontent.com/rtfd/readthedocs.org/master/docs/index.rst for inspiration

Welcome to the eHive user manual
================================

This manual describes how to run, develop, and troubleshoot eHive pipelines. It describes eHive's "swarm of autonomous agents" paradigm, shows how different components work together, and provides code examples. There are also links to API documentation for eHive classes.

The code is open source, and `available on GitHub`_.

.. _available on GitHub: https://github.com/Ensembl/ensembl-hive

The main documentation for eHive is organized into a couple sections:

* :ref:`user-docs`
* :ref:`dev-docs`

.. _user-docs:

User documentation
==================

.. toctree::
   :caption: Quickstart

   quickstart/install
   quickstart/quickstart

.. toctree::
   :caption: Walkthrough

   walkthrough/long_mult_walkthrough

.. toctree::
   :caption: Running pipelines

   running_pipelines/initializing
   running_pipelines/running
   running_pipelines/monitoring
   running_pipelines/management
   running_pipelines/tweaking
   running_pipelines/error-recovery
   running_pipelines/troubleshooting


.. toctree::
   :caption: Creating pipelines

   creating_pipelines/pipeconfigs
   creating_pipelines/dataflows
   creating_pipelines/semaphores
   creating_pipelines/accumulators
   creating_pipelines/parameters
   creating_pipelines/meadows_and_resources
   creating_pipelines/included_runnables


.. toctree::
   :caption: Creating runnables

   creating_runnables/runnables_overview
   creating_runnables/runnable_api
   creating_runnables/IO_and_errors


.. toctree::
   :caption: Advanced usage

   advanced_usage/mpi
   advanced_usage/slack
   advanced_usage/continuous_pipelines
   advanced_usage/json

.. toctree::
   :caption: External plugins

   contrib/alternative_meadows
   contrib/docker-swarm

.. toctree::
   :caption: Appendix
   :maxdepth: 1

   appendix/presentations
   appendix/analyses_pattern
   appendix/scripts
   appendix/hive_schema
   appendix/api
   appendix/changelog


.. _dev-docs:

Developer documentation
=======================

.. toctree::
   :caption: Developer documentation

   dev/development_guidelines
   dev/release_checklist
   dev/build_the_docs


Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`


..  LocalWords:  api
