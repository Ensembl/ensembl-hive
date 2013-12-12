EnsEMBL Hive
============

EnsEMBL Hive is a system for running computation pipelines on distributed computing resources - clusters, farms or grids.

The name "Hive" comes from the way pipelines are processed by a swarm of autonomous agents.

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
Hive pipeline databases are molded according to PipeConfig files which are Perl modules conforming to a special interface.
A PipeConfig file defines the stucture of the pipeline, which is a graph whose nodes are Analyses
(with their code, parameters and resource requirements) and edges are various dependency rules:
* Dataflow rules define how data that flows out of an Analysis can be used to trigger creation of Jobs in other Analyses

* Control rules define dependencies between Analyses as Jobs' containers ("Jobs of Analysis Y can only start when all Jobs of Analysis X are done")

* Semaphore rules define dependencies between individual Jobs on a more fine-grained level


There are also other parameters of Analyses that control, for example:
* how many Workers can simultaneously work on a given Analysis,
* how many times a Job should be tried until it is considered failed,
* what should be autimatically done with a Job if it needs more memory/time,
etc.

Contact us (mailing list)
-------------------------
EnsEMBL Hive was originally conceived and used within EnsEMBL Compara group
for running Comparative Genomics pipelines, but since then it has been separated
into a separate software tool and is used in many projects both in Genome Campus, Cambridge and outside.
There is a Hive users' mailing list for questions, suggestions, discussions and announcements.

To subscribe to it please visit:
        http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users

After subscribing  you will be able to post to:
        ehive-users@ebi.ac.uk

