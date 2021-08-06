eHive
=====

[![Travis Build Status](https://travis-ci.org/Ensembl/ensembl-hive.svg?branch=version/2.6)](https://travis-ci.org/Ensembl/ensembl-hive)
[![Coverage Status](https://coveralls.io/repos/Ensembl/ensembl-hive/badge.svg?branch=version/2.6&service=github)](https://coveralls.io/github/Ensembl/ensembl-hive?branch=version/2.6)
[![Documentation Status](https://readthedocs.org/projects/ensembl-hive/badge/?version=version-2.6)](http://ensembl-hive.readthedocs.io/en/version-2.6)
[![codecov](https://codecov.io/gh/Ensembl/ensembl-hive/branch/version%2F2.6/graph/badge.svg)](https://codecov.io/gh/Ensembl/ensembl-hive/branch/version%2F2.6)
[![Code Climate](https://codeclimate.com/github/Ensembl/ensembl-hive/badges/gpa.svg)](https://codeclimate.com/github/Ensembl/ensembl-hive)
[![Docker Build Status](https://img.shields.io/docker/build/ensemblorg/ensembl-hive.svg)](https://hub.docker.com/r/ensemblorg/ensembl-hive)

eHive is a system for running computation pipelines on distributed computing resources - clusters, farms or grids.

The name comes from the way pipelines are processed by a swarm of autonomous agents.

Available documentation
-----------------------

The main entry point is available online in the [user
manual](https://ensembl-hive.readthedocs.io/en/version-2.6/), from where it can
be downloaded for offline access.


eHive in a nutshell
-------------------

### Blackboard, Jobs and Workers

In the centre of each running pipeline is a database that acts as a blackboard with individual tasks to be run.
These tasks (we call them Jobs) are claimed and processed by "Worker bees" or just Workers - autonomous processes
that are continuously running on the compute farm and connect to the pipeline database to report about the progress of Jobs
or claim some more. When a Worker discovers that its predefined time is up or that there are no more Jobs to do,
it claims no more Jobs and exits the compute farm freeing the resources.

### Beekeeper

A separate Beekeeper process makes sure there are always enough Workers on the farm.
It regularly checks the states of both the blackboard and the farm and submits more Workers when needed.
There is no direct communication between Beekeeper and Workers, which makes the system rather fault-tolerant,
as crashing of any of the agents for whatever reason doesn't stop the rest of the system from running.

### Analyses

Jobs that share same code, common parameters and resource requirements are typically grouped into Analyses,
and generally an Analysis can be viewed as a "base class" for the Jobs that belong to it.
However in some sense an Analysis also acts as a "container" for them.

An analysis is implemented as a Runnable file which is a Perl, Python or
Java module conforming to a special interface. eHive provides some basic
Runnables, especially one that allows running arbitrary commands (programs
and scripts written in other languages).

### PipeConfig file defines Analyses and dependency rules of the pipeline

eHive pipeline databases are molded according to PipeConfig files which are Perl modules conforming to a special interface.
A PipeConfig file defines the stucture of the pipeline, which is a graph whose nodes are Analyses
(with their code, parameters and resource requirements) and edges are various dependency rules:

* Dataflow rules define how data that flows out of an Analysis can be used to trigger creation of Jobs in other Analyses
* Control rules define dependencies between Analyses as Jobs' containers ("Jobs of Analysis Y can only start when all Jobs of Analysis X are done")
* Semaphore rules define dependencies between individual Jobs on a more fine-grained level

There are also other parameters of Analyses that control, for example:

* how many Workers can simultaneously work on a given Analysis,
* how many times a Job should be tried until it is considered failed,
* what should be automatically done with a Job if it needs more memory/time,
  etc.

Grid scheduler and Meadows
--------------------------

eHive has a generic interface named _Meadow_ that describes how to interact with an underlying grid scheduler (submit jobs, query job's status, etc). eHive is compatible with
[IBM Platform LSF](http://www-03.ibm.com/systems/spectrum-computing/products/lsf/),
Sun Grid Engine (now known as Oracle Grid Engine),
[HTCondor](https://research.cs.wisc.edu/htcondor/),
[PBS Pro](http://www.pbspro.org),
[Docker Swarm](https://docs.docker.com/engine/swarm/) and maybe others. Read more about this on [the user manual](http://ensembl-hive.readthedocs.io/en/version-2.6/contrib/alternative_meadows.html).

Docker image
------------

We have a Docker image available on the [Docker
Hub](https://hub.docker.com/r/ensemblorg/ensembl-hive/). It can be used to
showcase eHive scripts (`init_pipeline.pl`, `beekeeper.pl`, `runWorker.pl`) in a
container

### Open a session in a new container (will run bash)

```bash
docker run -it ensemblorg/ensembl-hive
```

### Initialize and run a pipeline

```bash
docker run -it ensemblorg/ensembl-hive init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $URL
docker run -it ensemblorg/ensembl-hive beekeeper.pl -url $URL -loop -sleep 0.2
docker run -it ensemblorg/ensembl-hive runWorker.pl -url $URL
```

Docker Swarm
------------

Once packaged into Docker images, a pipeline can actually be run under the
Docker Swarm orchestrator, and thus on any cloud infrastructure that supports
it (e.g. [Amazon Web Services](https://docs.docker.com/docker-cloud/cloud-swarm/create-cloud-swarm-aws/),
[Microsoft Azure](https://docs.docker.com/docker-cloud/cloud-swarm/create-cloud-swarm-azure/)).

Read more about this on [the user manual](http://ensembl-hive.readthedocs.io/en/version-2.6/contrib/docker-swarm.html).

Contact us (mailing list)
-------------------------

eHive was originally conceived and used within EnsEMBL Compara group
for running Comparative Genomics pipelines, but since then it has been separated
into a separate software tool and is used in many projects both in Genome Campus, Cambridge and outside.
There is eHive users' mailing list for questions, suggestions, discussions and announcements.

To subscribe to it please visit <http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users>
