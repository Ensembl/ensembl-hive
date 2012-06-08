
-- The first 3 tables are from the ensembl core schema: meta, analysis and analysis_description.
-- We create them with the 'IF NOT EXISTS' option in case they already exist in the DB.

################################################################################
#
# Table structure for table 'meta' (FROM THE CORE SCHEMA)
#

CREATE TABLE IF NOT EXISTS meta (

  meta_id                     INT NOT NULL AUTO_INCREMENT,
  species_id                  INT UNSIGNED DEFAULT 1,
  meta_key                    VARCHAR(40) NOT NULL,
  meta_value                  TEXT NOT NULL,

  PRIMARY   KEY (meta_id),
  UNIQUE    KEY species_key_value_idx (species_id, meta_key, meta_value(255)),
            KEY species_value_idx (species_id, meta_value(255))

) COLLATE=latin1_swedish_ci ENGINE=MyISAM;


################################################################################
#
# Table structure for table 'analysis' (FROM THE CORE SCHEMA)
#
# semantics:
#
# analysis_id - internal id
# created
#   - date to distinguish newer and older versions off the same analysis. Not
#     well maintained so far.
# logic_name - string to identify the analysis. Used mainly inside pipeline.
# db, db_version, db_file
#  - db should be a database name, db version the version of that db
#    db_file the file system location of that database,
#    probably wiser to generate from just db and configurations
# program, program_version,program_file
#  - The binary used to create a feature. Similar semantic to above
# module, module_version
#  - Perl module names (RunnableDBS usually) executing this analysis.
# parameters - a paramter string which is processed by the perl module
# gff_source, gff_feature
#  - how to make a gff dump from features with this analysis


CREATE TABLE IF NOT EXISTS analysis (

  analysis_id                 int(10) unsigned NOT NULL AUTO_INCREMENT, # unique internal id
  created                     datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
  logic_name                  VARCHAR(40) NOT NULL,
  db                          VARCHAR(120),
  db_version                  VARCHAR(40),
  db_file                     VARCHAR(255),
  program                     VARCHAR(255),
  program_version             VARCHAR(40),
  program_file                VARCHAR(255),
  parameters                  TEXT,
  module                      VARCHAR(255),
  module_version              VARCHAR(40),
  gff_source                  VARCHAR(40),
  gff_feature                 VARCHAR(40),

  PRIMARY KEY (analysis_id),
  KEY logic_name_idx (logic_name),
  UNIQUE (logic_name)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


################################################################################
#
# Table structure for table 'analysis_description' (FROM THE CORE SCHEMA)
#

CREATE TABLE IF NOT EXISTS analysis_description (

  analysis_id                 int(10) unsigned NOT NULL,
  description                  TEXT,
  display_label                VARCHAR(255),
  displayable                  BOOLEAN NOT NULL DEFAULT 1,
  web_data                     TEXT,

  UNIQUE KEY analysis_idx (analysis_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;



#################### now, to the 'proper' Hive tables: ##############################


-- ----------------------------------------------------------------------------------
--
-- Table structure for table 'worker'
--
-- overview:
--   Table which tracks the workers of a hive as they exist out in the world.
--   Workers are created by inserting into this table so that there is only every
--   one instance of a worker object in the world.  As workers live and do work,
--   they update this table, and when they die they update.
--
-- semantics:
--

CREATE TABLE worker (
  worker_id        int(10) unsigned NOT NULL AUTO_INCREMENT,
  analysis_id      int(10) unsigned NOT NULL,
  meadow_type      varchar(40) NOT NULL,
  meadow_name      varchar(40) DEFAULT NULL,
  host	           varchar(40) DEFAULT NULL,
  process_id       varchar(40) DEFAULT NULL,
  work_done        int(11) DEFAULT '0' NOT NULL,
  status           enum('READY','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DEAD') DEFAULT 'READY' NOT NULL,
  born	           timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_check_in    datetime NOT NULL,
  died             datetime DEFAULT NULL,
  cause_of_death   enum('', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'FATALITY') DEFAULT '' NOT NULL,

  PRIMARY KEY (worker_id),
  INDEX analysis_status (analysis_id, status)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'dataflow_rule'
--
-- overview:
--   Extension of simple_rule design except that goal(to) is now in extended URL format e.g.
--   mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test?analysis.logic_name='blast_NCBI34'
--   (full network address of an analysis).  The only requirement is that there are rows in 
--   the job, analysis, dataflow_rule, and worker tables so that the following join
--   works on the same database 
--   WHERE analysis.analysis_id = dataflow_rule.from_analysis_id 
--   AND   analysis.analysis_id = job.analysis_id
--   AND   analysis.analysis_id = worker.analysis_id
--
--   These are the rules used to create entries in the job table where the
--   input_id (control data) is passed from one analysis to the next to define work.
--  
--   The analysis table will be extended so that it can specify different read and write
--   databases, with the default being the database the analysis is on
--
-- semantics:
--   dataflow_rule_id     - internal ID
--   from_analysis_id     - foreign key to analysis table analysis_id
--   branch_code          - branch_code of the fan
--   funnel_dataflow_fule_id - dataflow_rule_id of the semaphored funnel (is NULL by default, which means dataflow is not semaphored)
--   to_analysis_url      - foreign key to net distributed analysis logic_name reference
--   input_id_template    - a template for generating a new input_id (not necessarily a hashref) in this dataflow; if undefined is kept original

CREATE TABLE dataflow_rule (
  dataflow_rule_id    int(10) unsigned NOT NULL AUTO_INCREMENT,
  from_analysis_id    int(10) unsigned NOT NULL,
  branch_code         int(10) default 1 NOT NULL,
  funnel_dataflow_rule_id  int(10) unsigned default NULL,
  to_analysis_url     varchar(255) default '' NOT NULL,
  input_id_template   TEXT DEFAULT NULL,

  PRIMARY KEY (dataflow_rule_id),
  UNIQUE KEY (from_analysis_id, branch_code, funnel_dataflow_rule_id, to_analysis_url, input_id_template(512))

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'analysis_ctrl_rule'
--
-- overview:
--   These rules define a higher level of control.  These rules are used to turn
--   whole anlysis nodes on/off (READY/BLOCKED).
--   If any of the condition_analyses are not 'DONE' the ctrled_analysis is set BLOCKED
--   When all conditions become 'DONE' then ctrled_analysis is set to READY
--   The workers switch the analysis.status to 'WORKING' and 'DONE'.
--   But any moment if a condition goes false, the analysis is reset to BLOCKED.
--
--   This process of watching conditions and flipping the ctrled_analysis state
--   will be accomplished by another automous agent (CtrlWatcher.pm)
--
-- semantics:
--   condition_analysis_url  - foreign key to net distributed analysis reference
--   ctrled_analysis_id      - foreign key to analysis table analysis_id

CREATE TABLE analysis_ctrl_rule (
  condition_analysis_url     varchar(255) default '' NOT NULL,
  ctrled_analysis_id         int(10) unsigned NOT NULL,

  UNIQUE (condition_analysis_url, ctrled_analysis_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'job'
--
-- overview:
--   The job is the heart of this system.  It is the kiosk or blackboard
--   where workers find things to do and then post work for other works to do.
--   These jobs are created prior to work being done, are claimed by workers,
--   are updated as the work is done, with a final update on completion.
--
-- semantics:
--   job_id                  - autoincrement id
--   prev_job_id             - previous job which created this one (and passed input_id)
--   analysis_id             - the analysis_id needed to accomplish this job.
--   input_id                - input data passed into Analysis:RunnableDB to control the work
--   worker_id               - link to worker table to define which worker claimed this job
--   status                  - state the job is in
--   retry_count             - number times job had to be reset when worker failed to run it
--   completed               - datetime when job was completed
--
--   semaphore_count         - if this count is >0, the job is conditionally blocked (until this count drops to 0 or below).
--                              Default=0 means "nothing is blocking me by default".
--   semaphored_job_id       - the job_id of job S that is waiting for this job to decrease S's semaphore_count.
--                              Default=NULL means "I'm not blocking anything by default".

CREATE TABLE job (
  job_id                    int(10) NOT NULL AUTO_INCREMENT,
  prev_job_id               int(10) DEFAULT NULL,  # the job that created this one using a dataflow rule
  analysis_id               int(10) unsigned NOT NULL,
  input_id                  char(255) NOT NULL,
  worker_id                 int(10) unsigned DEFAULT NULL,
  status                    enum('READY','BLOCKED','CLAIMED','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL,
  retry_count               int(10) default 0 NOT NULL,
  completed                 datetime DEFAULT NULL,
  runtime_msec              int(10) default NULL, 
  query_count               int(10) default NULL, 

  semaphore_count           int(10) NOT NULL default 0,
  semaphored_job_id         int(10) DEFAULT NULL,

  PRIMARY KEY                  (job_id),
  UNIQUE KEY input_id_analysis (input_id, analysis_id),
  INDEX analysis_status_sema_retry (analysis_id, status, semaphore_count, retry_count),
  INDEX worker_id              (worker_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'job_message'
--
-- overview:
--      In case a job throws a message (via die/throw), this message is registered in this table.
--      It may or may not indicate that the job was unsuccessful via is_error flag.
--
-- semantics:
--       job_message_id     - an autoincremented primary id of the message
--               job_id     - the id of the job that threw the message
--            worker_id     - the worker in charge of the job at the moment
--                 time     - when the message was thrown
--                retry     - retry_count of the job when the message was thrown
--               status     - of the job when the message was thrown
--                  msg     - string that contains the message
--             is_error     - binary flag

CREATE TABLE job_message (
  job_message_id            int(10) NOT NULL AUTO_INCREMENT,
  job_id                    int(10) NOT NULL,
  worker_id                 int(10) unsigned NOT NULL,
  time                      timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  retry                     int(10) DEFAULT 0 NOT NULL,
  status                    enum('UNKNOWN', 'COMPILATION', 'GET_INPUT', 'RUN', 'WRITE_OUTPUT', 'PASSED_ON') DEFAULT 'UNKNOWN',
  msg                       text,
  is_error                  boolean,

  PRIMARY KEY               (job_message_id),
  INDEX worker_id           (worker_id),
  INDEX job_id              (job_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'job_file'
--
-- overview:
--   Table which holds paths to files created by jobs
--   e.g. STDOUT STDERR, temp directory
--   or output data files created by the RunnableDB
--   There can only be one entry of a certain type for a given job
--
-- semantics:
--   job_id             - foreign key
--   worker_id          - link to worker table to define which worker claimed this job
--   retry              - copy of retry_count of job as it was run
--   stdout_file        - path to the job's STDOUT log
--   stderr_file        - path to the job's STDERR log

CREATE TABLE job_file (
  job_id                int(10) NOT NULL,
  retry                 int(10) NOT NULL,
  worker_id             int(10) unsigned NOT NULL,
  stdout_file           varchar(255),
  stderr_file           varchar(255),

  UNIQUE KEY job_retry  (job_id, retry),
  INDEX worker_id           (worker_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'analysis_data'
--
-- overview:
--   Table which holds LONGTEXT data for use by the analysis system.
--   This data is general purpose and it's up to each analysis to
--   determine how to use it
--
-- semantics:
--   analysis_data_id   - primary id
--   data               - text blob which holds the data

CREATE TABLE analysis_data (
  analysis_data_id  int(10) NOT NULL AUTO_INCREMENT,
  data              longtext,

  PRIMARY KEY (analysis_data_id),
  KEY data (data(100))
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


CREATE TABLE resource_description (
    rc_id                 int(10) unsigned DEFAULT 0 NOT NULL,
    meadow_type           varchar(40) NOT NULL,
    parameters            varchar(255) DEFAULT '' NOT NULL,

    PRIMARY KEY(rc_id, meadow_type)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


CREATE TABLE resource_class (
    resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,     # unique internal id
    name                varchar(40) NOT NULL,

    PRIMARY KEY(resource_class_id),
    UNIQUE KEY(name)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'analysis_stats'
--
-- overview:
--   Parallel table to analysis which provides high level statistics on the
--   state of an analysis and it's jobs.  Used to provide a fast overview, and to
--   provide final approval of 'DONE' which is used by the blocking rules to determine
--   when to unblock other analyses.  Also provides
--
-- semantics:
--   analysis_id          - foreign key to analysis table
--   status               - overview status of the jobs (cached state)
--   failed_job_tolerance - % of tolerated failed jobs
--   rc_id                - resource class id (analyses are grouped into disjoint classes)

CREATE TABLE analysis_stats (
  analysis_id           int(10) unsigned NOT NULL,
  status                enum('BLOCKED', 'LOADING', 'SYNCHING', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE', 'FAILED')
                          DEFAULT 'READY' NOT NULL,
  batch_size            int(10) default 1 NOT NULL,
  avg_msec_per_job      int(10) default 0 NOT NULL,
  avg_input_msec_per_job      int(10) default 0 NOT NULL,
  avg_run_msec_per_job      int(10) default 0 NOT NULL,
  avg_output_msec_per_job      int(10) default 0 NOT NULL,
  hive_capacity         int(10) default 1 NOT NULL,
  behaviour             enum('STATIC', 'DYNAMIC') DEFAULT 'STATIC' NOT NULL,
  input_capacity        int(10) default 4 NOT NULL,
  output_capacity       int(10) default 4 NOT NULL,
  total_job_count       int(10) NOT NULL,
  unclaimed_job_count   int(10) NOT NULL,
  done_job_count        int(10) NOT NULL,
  max_retry_count       int(10) default 3 NOT NULL,
  failed_job_count      int(10) NOT NULL,
  failed_job_tolerance  int(10) default 0 NOT NULL,
  num_running_workers   int(10) default 0 NOT NULL,
  num_required_workers  int(10) NOT NULL,
  last_update           datetime NOT NULL,
  sync_lock             int(10) default 0 NOT NULL,
  rc_id                 int(10) unsigned default 0 NOT NULL,
  can_be_empty          TINYINT UNSIGNED DEFAULT 0 NOT NULL,
  priority              TINYINT DEFAULT 0 NOT NULL,
  
  UNIQUE KEY   (analysis_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


CREATE TABLE analysis_stats_monitor (
  time                  datetime NOT NULL default '0000-00-00 00:00:00',
  analysis_id           int(10) unsigned NOT NULL,
  status                enum('BLOCKED', 'LOADING', 'SYNCHING', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE', 'FAILED')
                          DEFAULT 'READY' NOT NULL,
  batch_size            int(10) default 1 NOT NULL,
  avg_msec_per_job      int(10) default 0 NOT NULL,
  avg_input_msec_per_job      int(10) default 0 NOT NULL,
  avg_run_msec_per_job      int(10) default 0 NOT NULL,
  avg_output_msec_per_job      int(10) default 0 NOT NULL,
  hive_capacity         int(10) default 1 NOT NULL,
  behaviour             enum('STATIC', 'DYNAMIC') DEFAULT 'STATIC' NOT NULL,
  input_capacity        int(10) default 4 NOT NULL,
  output_capacity       int(10) default 4 NOT NULL,
  total_job_count       int(10) NOT NULL,
  unclaimed_job_count   int(10) NOT NULL,
  done_job_count        int(10) NOT NULL,
  max_retry_count       int(10) default 3 NOT NULL,
  failed_job_count      int(10) NOT NULL,
  failed_job_tolerance  int(10) default 0 NOT NULL,
  num_running_workers   int(10) default 0 NOT NULL,
  num_required_workers  int(10) NOT NULL,
  last_update           datetime NOT NULL,
  sync_lock             int(10) default 0 NOT NULL,
  rc_id                 int(10) unsigned default 0 NOT NULL,
  can_be_empty          TINYINT UNSIGNED DEFAULT 0 NOT NULL,
  priority              TINYINT DEFAULT 0 NOT NULL

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

-- ---------------------------------------------------------------------------------
--
-- Table structure for table 'monitor'
--
-- overview:
--   This table stores information about hive performance.
--
-- semantics:
--   time           - datetime
--   workers        - number of running workers
--   throughput     - average numb of completed jobs per sec. of the hive
--                    (this number is calculated using running workers only)
--   per_worker     - average numb of completed jobs per sec. per worker
--                    (this number is calculated using running workers only)
--   analysis       - analysis(es) running at that time

CREATE TABLE monitor (
  time                  datetime NOT NULL default '0000-00-00 00:00:00',
  workers               int(10) NOT NULL default '0',
  throughput            float default NULL,
  per_worker            float default NULL,
  analysis              varchar(255) default NULL  # not just one, but a list of logic_names

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


# Auto add schema version to database (should be overridden by Compara's table.sql)
INSERT IGNORE INTO meta (species_id, meta_key, meta_value) VALUES (NULL, 'schema_version', '67');

