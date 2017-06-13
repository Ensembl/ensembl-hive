.. ehive_user_manual documentation master file, created by
   sphinx-quickstart on Thu Dec 15 12:59:35 2016.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

.. Have a look at https://raw.githubusercontent.com/rtfd/readthedocs.org/master/docs/index.rst for inspiration

Welcome to the eHive user manual
================================

eHive is great, and the user manual is great.

The code is open source, and `available on GitHub`_.

.. _available on GitHub: http://github.com/Ensembl/ensembl-hive

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

   running_pipelines/running
   running_pipelines/monitoring
   running_pipelines/management
   running_pipelines/tweaking
   running_pipelines/error-recovery


.. toctree::
   :caption: Creating pipelines

   creating_pipelines/events
   creating_pipelines/dataflows
   creating_pipelines/dataflow_targets
   creating_pipelines/accumulators
   creating_pipelines/parameters
   creating_pipelines/semaphores
   creating_pipelines/pipeconfigs


.. toctree::
   :caption: Creating runnables

   creating_runnables/runnables


.. toctree::
   :caption: Advanced usage

   advanced_usage/mpi
   advanced_usage/slack


.. toctree::
   :caption: Appendix
   :maxdepth: 1

   appendix/scripts


.. _dev-docs:

Developer documentation
=======================

TODO


Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`

