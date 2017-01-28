NAME
====

::

        beekeeper.pl [options]

DESCRIPTION
===========

::

        The Beekeeper is in charge of interfacing between the Queen and a compute resource or 'compute farm'.
        Its job is to initialize/sync the eHive database (via the Queen), query the Queen if it needs any workers
        and to send the requested number of workers to open machines via the runWorker.pl script.

        It is also responsible for interfacing with the Queen to identify workers which died
        unexpectedly so that she can free the dead workers and reclaim unfinished jobs.

USAGE EXAMPLES
==============

::

            # Usually run after the pipeline has been created to calculate the internal statistics necessary for eHive functioning
        beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname -sync

            # Do not run any additional Workers, just check for the current status of the pipeline:
        beekeeper.pl -url mysql://username:secret@hostname:port/ehive_dbname

            # Run the pipeline in automatic mode (-loop), run all the workers locally (-meadow_type LOCAL) and allow for 3 parallel workers (-total_running_workers_max 3)
        beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -meadow_type LOCAL -total_running_workers_max 3 -loop

            # Run in automatic mode, but only restrict to running blast-related analyses with the exception of analyses 4..6
        beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -analyses_pattern 'blast%-4..6' -loop

            # Restrict the normal execution to one iteration only - can be used for testing a newly set up pipeline
        beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -run

            # Reset failed 'buggy_analysis' jobs to 'READY' state, so that they can be run again
        beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -analyses_pattern buggy_analysis -reset_failed_jobs

            # Do a cleanup: find and bury dead workers, reclaim their jobs
        beekeeper.pl -url mysql://username:secret@hostname:port/long_mult_test -dead

OPTIONS
=======

Connection parameters
---------------------

::

        -reg_conf <path>       : path to a Registry configuration file
        -reg_type <string>     : type of the registry entry ('hive', 'core', 'compara', etc. - defaults to 'hive')
        -reg_alias <string>    : species/alias name for the Hive DBAdaptor
        -url <url string>      : url defining where hive database is located
        -nosqlvc <0|1>         : skip sql version check if 1

Configs overriding
------------------

::

        -config_file <string>  : json file (with absolute path) to override the default configurations (could be multiple)

Looping control
---------------

::

        -loop                  : run autonomously, loops and sleeps. Equivalent to -loop_until ANALYSIS_FAILURE
        -loop_until            : sets the level of event that will cause the beekeeper to stop looping:
                               : JOB_FAILURE      = stop looping if any job fails
                               : ANALYSIS_FAILURE = stop looping if any analysis has job failures exceeding
                               :     its fault tolerance
                               : NO_WORK          = ignore job and analysis faliures, keep looping until there is no work
                               : FOREVER          = ignore failures and no work, keep looping
        -keep_alive            : (Deprecated) alias for -loop_until FOREVER
        -max_loops <num>       : perform max this # of loops in autonomous mode. The beekeeper will stop when
                               : it has performed max_loops loops, even in FOREVER mode
        -job_id <job_id>       : run 1 iteration for this job_id
        -run                   : run 1 iteration of automation loop
        -sleep <num>           : when looping, sleep <num> minutes (default 1 min)

Current Meadow control
----------------------

::

        -meadow_type <string>               : the desired Meadow class name, such as 'LSF' or 'LOCAL'
        -total_running_workers_max <num>    : max # workers to be running in parallel
        -submit_workers_max <num>           : max # workers to create per loop iteration
        -submission_options <string>        : passes <string> to the Meadow submission command as <options> (formerly lsf_options)
        -submit_log_dir <dir>               : record submission output+error streams into files under the given directory (to see why some workers fail after submission)

Worker control
--------------

::

        -analyses_pattern <string>  : restrict the sync operation, printing of stats or looping of the beekeeper to the specified subset of analyses
        -can_respecialize <0|1>     : allow workers to re-specialize into another analysis (within resource_class) after their previous analysis was exhausted
        -force                      : run all workers with -force (see runWorker.pl)
        -killworker <worker_id>     : kill worker by worker_id
        -life_span <num>            : number of minutes each worker is allowed to run
        -job_limit <num>            : #jobs to run before worker can die naturally
        -retry_throwing_jobs <0|1>  : if a job dies *knowingly*, should we retry it by default?
        -hive_log_dir <path>        : directory where stdout/stderr of the hive is redirected
        -debug <debug_level>        : set debug level of the workers

Other commands/options
----------------------

::

        -help                  : print this help
        -versions              : report both Hive code version and Hive database schema version
        -dead                  : detect all unaccounted dead workers and reset their jobs for resubmission
        -sync                  : re-synchronize the hive
        -unkwn                 : detect all workers in UNKWN state and reset their jobs for resubmission (careful, they *may* reincarnate!)
        -alldead               : tell the database all workers are dead (no checks are performed in this mode, so be very careful!)
        -balance_semaphores    : set all semaphore_counts to the numbers of unDONE fan jobs (emergency use only)
        -worker_stats          : show status of each running worker
        -failed_jobs           : show all failed jobs
        -job_output <job_id>   : print details for one job
        -reset_job_id <num>    : reset a job back to READY so it can be rerun
        -reset_failed_jobs     : reset FAILED jobs of -analyses_filter'ed ones back to READY so they can be rerun
        -reset_done_jobs       : reset DONE and PASSED_ON jobs of -analyses_filter'ed ones back to READY so they can be rerun
        -reset_all_jobs        : reset FAILED, DONE and PASSED_ON jobs of -analyses_filter'ed ones back to READY so they can be rerun
        -forgive_failed_jobs   : mark FAILED jobs of -analyses_filter'ed ones as DONE, and update their semaphores. NOTE: This does not make them dataflow
        -discard_ready_jobs    : mark READY jobs of -analyses_filter'ed ones as DONE, and update their semaphores. NOTE: This does not make them dataflow
        -unblock_semaphored_jobs : set SEMAPHORED jobs of -analyses_filter'ed ones to READY so they can start

LICENSE
=======

::

        Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
        Copyright [2016] EMBL-European Bioinformatics Institute

        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

             http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License
        is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and limitations under the License.

CONTACT
=======

::

        Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

