
Runnables Overview
==================

The code a worker actually runs to accomplish its task is in a module called a "runnable." At its simplest, a runnable is simply a bit of code that implements either:

   - Bio::EnsEMBL::Hive::Process (Perl)

   - eHive.Process (Python)

   - org.ensembl.hive.BaseRunnable (Java)

When a worker specializes to perform a job, it compiles and runs the runnable associated with the job's analysis.

The ...Process base class (in whichever language) provides a common interface for the workers. In particular, it provides a set of methods that are guaranteed to be called in order:

   #. pre_cleanup()

   #. fetch_input()

   #. run()

   #. write_output()

   #. post_healthcheck()

   #. post_cleanup()

Note that the method names are suggestions. With the exception of pre_cleanup and write_output, there is no special behaviour for these methods except for the order in which they are run. There is no need to implement all (or indeed, any) of these methods. If nothing is provided for a method, the default is to do nothing.

There are a number of example runnables provided with eHive. They can be found in two locations: 

   - Utility runnables are located in ``modules/Bio/EnsEMBL/Hive/RunnableDB/``.

   - Runnables associated with example pipelines can be found in the ``RunnableDB/`` subdirectories under the example directories in ``modules/Bio/EnsEMBL/Hive/Examples/``.

pre_cleanup
===========

If the job has a retry count greater than zero, then pre_cleanup() is the first method called when a worker runs a job. This provides an opportunity to clean up database entries or files that may be leftover from a failed attempt to run the job before trying again.

fetch_input
===========

The fetch_input() method is the first method called the first time a job is run (if a job has a retry count greater than zero, then pre_cleanup() will be the first method called). This method is provided to check that input parameters exist and are valid. The benefits of putting input parameter checks here include:

   - Making the code easier to understand and maintain; users of the runnable will know where to look to quickly discover which parameters are required or optional.

   - If there are problems with input parameters, the job will fail quickly.

run
===

The run() method is called after fetch_input() completes. This method is provided as a place to put the main analysis logic of the runnable. 

write_output
============

The write_output() method is called after run() completes. This method is provided as a place to put statements that create dataflow events. It is generally good practice to put dataflow statements here to aid users in understanding and maintaining the runnable.

post_healthcheck
================

The post_healthcheck method is called after write_output() completes. This method is provided as a place to verify that the runnable executed correctly.

post_cleanup
============

There are two possible triggers for calling the post_cleanup() method. It is called immediately after post_healthcheck(), and it is called (if possible) if a job is failing (e.g. if a die statement is reached elsewhere in the runnable). Therefore, this method is somewhat similar to an exception handling catch block. This method should contain code performing cleanup that needs happen regardless of whether or not the job completed successfully, such as closing database connections or filehandles.
