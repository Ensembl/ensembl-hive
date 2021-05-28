eHive
=====

---

:warning: This branch is not maintained any more ! :warning:

---



eHive is a system for running computation pipelines on distributed computing resources - clusters, farms or grids.

The name comes from the way pipelines are processed by a swarm of autonomous agents.

Blackboard, Jobs and Workers
----------------------------
In the centre of each running pipeline is a database that acts as a blackboard with individual tasks to be run.
These tasks (we call them Jobs) are claimed and processed by "Worker bees" or just Workers - autonomous processes
that are continuously running on the compute farm and connect to the pipeline database to report about the progress of Jobs
or claim some more. When a Worker discovers that its predefined time is up or that there are no more Jobs to do,
it claims no more Jobs and exits the compute farm freeing the resources.

Beekeeper
---------
A separate Beekeeper process makes sure there are always enough Workers on the farm.
It regularly checks the states of both the blackboard and the farm and submits more Workers when needed.
There is no direct communication between Beekeeper and Workers, which makes the system rather fault-tolerant,
as crashing of any of the agents for whatever reason doesn't stop the rest of the system from running. 

Analyses
--------
Jobs that share same code, common parameters and resource requirements are typically grouped into Analyses,
and generally an Analysis can be viewed as a "base class" for the Jobs that belong to it.
However in some sense an Analysis also acts as a "container" for them.

PipeConfig file defines Analyses and dependency rules of the pipeline
---------------------------------------------------------------------
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

eHive has a generic interface named _Meadow_ that describes how to interact with an underlying grid scheduler (submit jobs, query job's status, etc). eHive ships two meadow implementations:
* **LOCAL**. A simple meadow that submits jobs locally via `system()` (i.e. `fork()`). It is inherently limited by the specification of the machine beekeeper is running on.
* **LSF**. A meadow that supports [IBM Platform LSF](http://www-03.ibm.com/systems/spectrum-computing/products/lsf/)

Both are extensively used by the Ensembl project and are regularly updated. The LSF meadow supports workloads reaching thousands of parallel jobs.

External users have contributed other meadows:
* **SGE**. A meadow that supports Sun Grid Engine (now known as Oracle Grid Engine). Available for download on GitHub at [Ensembl/ensembl-hive-sge](https://github.com/Ensembl/ensembl-hive-sge).

The table below lists the capabilities of each meadow, and whether they are available and implemented:

| Capability                               | LOCAL         | LSF | SGE             |
| :--------------------------------------- | ------------- | ----| --------------- |
| Submit jobs                              | Yes           | Yes | Yes             |
| Query job status                         | Yes           | Yes | Yes             |
| Kill job                                 | Yes           | Yes | Yes             |
| Job limiter and resource management      | Not available | Yes | Yes             |
| Post-mortem inspection of resource usage | Not available | Yes | Not implemented |


Available documentation
-----------------------
The main entry point is in [**docs/index.html**](https://rawgit.com/Ensembl/ensembl-hive/version/2.4/docs/index.html) and can also be browsed offline.

There is preliminary support for Python3, see [the Doxygen
documentation](https://rawgit.com/Ensembl/ensembl-hive/version/2.4/wrappers/python3/doxygen/index.html) and
[an example PipeConfig
file](modules/Bio/EnsEMBL/Hive/Examples/LongMult/PipeConfig/LongMultSt_pyconf.pm#L139).

Contact us (mailing list)
-------------------------
eHive was originally conceived and used within EnsEMBL Compara group
for running Comparative Genomics pipelines, but since then it has been separated
into a separate software tool and is used in many projects both in Genome Campus, Cambridge and outside.
There is eHive users' mailing list for questions, suggestions, discussions and announcements.

To subscribe to it please visit (http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users)

