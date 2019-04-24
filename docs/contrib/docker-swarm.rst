
.. _docker-swarm-intro:

Docker Swarm
============

Docker Swarm is Docker's own orchestration system. It allows running and
managing Docker containers as services. eHive can be packaged as docker
image (see on the `Docker hub <https://hub.docker.com/r/ensemblorg/ensembl-hive>`__).
It also has a `Meadow plugin <https://github.com/Ensembl/ensembl-hive-docker-swarm>`__
to leverage the Docker Swarm API and use it like any job scheduler.

Here is some documentation about setting this up.

.. toctree::
   :maxdepth: 8

   docker-swarm/tutorial
   docker-swarm/howto
   docker-swarm/dev_notes

