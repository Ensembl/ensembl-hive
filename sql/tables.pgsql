/*
    This is PostgreSQL version of EnsEMBL Hive database schema file.

    It has been annotated with @-tags.
    The following command is used to create HTML documentation:
        perl $ENSEMBL_CVS_ROOT_DIR/ensembl-production/scripts/sql2html.pl \
            -i $ENSEMBL_CVS_ROOT_DIR/ensembl-hive/sql/tables.pgsql -d Hive -intro $ENSEMBL_CVS_ROOT_DIR/ensembl-hive/docs/hive_schema.inc \
            -sort_headers 0 -sort_tables 0 -o $ENSEMBL_CVS_ROOT_DIR/ensembl-hive/docs/hive_schema.html


    Adding the following line into the header of the previous output will make it look prettier:
        <link rel="stylesheet" type="text/css" media="all" href="ehive_doc.css" />




LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

*/


/**
@header Pipeline structure
@colour #C70C09
*/

/**
@table  hive_meta

@colour #000000

@desc This table keeps several important hive-specific pipeline-wide key-value pairs
        such as hive_sql_schema_version, hive_use_triggers and hive_pipeline_name.

@column meta_key        the KEY of KEY-VALUE pairs (primary key)
@column meta_value      the VALUE of KEY-VALUE pairs
*/

CREATE TABLE hive_meta (
    meta_key                VARCHAR(255) NOT NULL PRIMARY KEY,
    meta_value              TEXT

);


/**
@table  pipeline_wide_parameters

@colour #000000

@desc This table contains a simple hash between pipeline_wide_parameter names and their values.
      The same data used to live in 'meta' table until both the schema and the API were finally separated from Ensembl Core.

@column param_name      the KEY of KEY-VALUE pairs (primary key)
@column param_value     the VALUE of KEY-VALUE pairs
*/

CREATE TABLE pipeline_wide_parameters (
    param_name              VARCHAR(255) NOT NULL PRIMARY KEY,
    param_value             TEXT

);
CREATE        INDEX ON pipeline_wide_parameters (param_value);


/**
@table  analysis_base

@colour #C70C09

@desc   Each Analysis is a node of the pipeline diagram.
        It acts both as a "class" to which Jobs belong (and inherit from it certain properties)
        and as a "container" for them (Jobs of an Analysis can be blocking all Jobs of another Analysis).

@column analysis_id             a unique ID that is also a foreign key to most of the other tables
@column logic_name              the name of the Analysis object
@column module                  the name of the module / package that runs this Analysis
@column language                the language of the module, if not Perl
@column parameters              a stingified hash of parameters common to all jobs of the Analysis
@column resource_class_id       link to the resource_class table
@column failed_job_tolerance    % of tolerated failed Jobs
@column max_retry_count         how many times a job of this Analysis will be retried (unless there is no point)
@column can_be_empty            if TRUE, this Analysis will not be blocking if/while it doesn't have any jobs
@column priority                an Analysis with higher priority will be more likely chosen on Worker's specialization
@column meadow_type             if defined, forces this Analysis to be run only on the given Meadow
@column analysis_capacity       if defined, limits the number of Workers of this particular Analysis that are allowed to run in parallel
*/

CREATE TABLE analysis_base (
    analysis_id             SERIAL PRIMARY KEY,
    logic_name              VARCHAR(255) NOT NULL,
    module                  VARCHAR(255) NOT NULL,
    language                VARCHAR(255),
    parameters              TEXT,
    resource_class_id       INTEGER     NOT NULL,
    failed_job_tolerance    INTEGER     NOT NULL DEFAULT 0,
    max_retry_count         INTEGER     NOT NULL DEFAULT 3,
    can_be_empty            SMALLINT    NOT NULL DEFAULT 0,
    priority                SMALLINT    NOT NULL DEFAULT 0,
    meadow_type             VARCHAR(255)          DEFAULT NULL,
    analysis_capacity       INTEGER              DEFAULT NULL,

    UNIQUE  (logic_name)
);


/**
@table  analysis_stats

@colour #C70C09

@desc   Parallel table to analysis_base which provides high level statistics on the
        state of an analysis and it's jobs.  Used to provide a fast overview, and to
        provide final approval of 'DONE' which is used by the blocking rules to determine
        when to unblock other analyses.  Also provides

@column analysis_id             foreign-keyed to the corresponding analysis_base entry
@column batch_size              how many jobs are claimed in one claiming operation before Worker starts executing them
@column hive_capacity           a reciprocal limiter on the number of Workers running at the same time (dependent on Workers of other Analyses)
@column status                  cached state of the Analysis

@column total_job_count         total number of Jobs of this Analysis
@column semaphored_job_count    number of Jobs of this Analysis that are in SEMAPHORED state
@column ready_job_count         number of Jobs of this Analysis that are in READY state
@column done_job_count          number of Jobs of this Analysis that are in DONE state
@column failed_job_count        number of Jobs of this Analysis that are in FAILED state

@column num_running_workers     number of running Workers of this Analysis

@column behaviour               whether hive_capacity is set or is dynamically calculated based on timers
@column input_capacity          used to compute hive_capacity in DYNAMIC mode
@column output_capacity         used to compute hive_capacity in DYNAMIC mode

@column avg_msec_per_job        weighted average used to compute DYNAMIC hive_capacity
@column avg_input_msec_per_job  weighted average used to compute DYNAMIC hive_capacity
@column avg_run_msec_per_job    weighted average used to compute DYNAMIC hive_capacity
@column avg_output_msec_per_job weighted average used to compute DYNAMIC hive_capacity

@column when_updated            when this entry was last updated
@column sync_lock               a binary lock flag to prevent simultaneous updates
*/

CREATE TYPE analysis_status AS ENUM ('BLOCKED', 'LOADING', 'SYNCHING', 'EMPTY', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE', 'FAILED');
CREATE TYPE analysis_behaviour AS ENUM ('STATIC', 'DYNAMIC');
CREATE TABLE analysis_stats (
    analysis_id             INTEGER     NOT NULL,
    batch_size              INTEGER     NOT NULL DEFAULT 1,
    hive_capacity           INTEGER              DEFAULT NULL,
    status                  analysis_status NOT NULL DEFAULT 'EMPTY',

    total_job_count         INTEGER     NOT NULL DEFAULT 0,
    semaphored_job_count    INTEGER     NOT NULL DEFAULT 0,
    ready_job_count         INTEGER     NOT NULL DEFAULT 0,
    done_job_count          INTEGER     NOT NULL DEFAULT 0,
    failed_job_count        INTEGER     NOT NULL DEFAULT 0,

    num_running_workers     INTEGER     NOT NULL DEFAULT 0,

    behaviour               analysis_behaviour NOT NULL DEFAULT 'STATIC',
    input_capacity          INTEGER     NOT NULL DEFAULT 4,
    output_capacity         INTEGER     NOT NULL DEFAULT 4,

    avg_msec_per_job        INTEGER              DEFAULT NULL,
    avg_input_msec_per_job  INTEGER              DEFAULT NULL,
    avg_run_msec_per_job    INTEGER              DEFAULT NULL,
    avg_output_msec_per_job INTEGER              DEFAULT NULL,

    when_updated            TIMESTAMP            DEFAULT NULL,
    sync_lock               SMALLINT    NOT NULL DEFAULT 0,

    PRIMARY KEY (analysis_id)
);


/**
@table  dataflow_rule

@colour #C70C09

@desc Each entry of this table defines a starting point for dataflow (via from_analysis_id and branch_code)
      to which point a group of dataflow_target entries can be linked. This grouping is used in two ways:
      (1) dataflow_target entries that link into the same dataflow_rule share the same from_analysis, branch_code and funnel_dataflow_rule
      (2) to define the conditions for DEFAULT or ELSE case (via excluding all conditions explicitly listed in the group)

@column dataflow_rule_id        internal ID
@column from_analysis_id        foreign key to analysis table analysis_id
@column branch_code             branch_code of the fan
@column funnel_dataflow_rule_id dataflow_rule_id of the semaphored funnel (is NULL by default, which means dataflow is not semaphored)
*/

CREATE TABLE dataflow_rule (
    dataflow_rule_id        SERIAL PRIMARY KEY,
    from_analysis_id        INTEGER     NOT NULL,
    branch_code             INTEGER     NOT NULL DEFAULT 1,
    funnel_dataflow_rule_id INTEGER              DEFAULT NULL
);


/**
@table  dataflow_target

@colour #C70C09

@desc This table links specific conditions with the target object (Analysis/Table/Accu) and optional input_id_template.

@column source_dataflow_rule_id foreign key to the dataflow_rule object that defines grouping (see description of dataflow_rule table)
@column on_condition            param-substitutable string evaluated at the moment of dataflow event that defines whether or not this case produces any dataflow; NULL means DEFAULT or ELSE
@column input_id_template       a template for generating a new input_id (not necessarily a hashref) in this dataflow; if undefined is kept original
@column to_analysis_url         the URL of the dataflow target object (Analysis/Table/Accu)
*/

CREATE TABLE dataflow_target (
    source_dataflow_rule_id INTEGER     NOT NULL,
    on_condition            VARCHAR(255)          DEFAULT NULL,
    input_id_template       TEXT                  DEFAULT NULL,
    to_analysis_url         VARCHAR(255) NOT NULL DEFAULT '',       -- to be renamed 'target_url'

    UNIQUE (source_dataflow_rule_id, on_condition, input_id_template, to_analysis_url)
);



/**
@table  analysis_ctrl_rule

@colour #C70C09

@desc   These rules define a higher level of control.
        These rules are used to turn whole anlysis nodes on/off (READY/BLOCKED).
        If any of the condition_analyses are not 'DONE' the ctrled_analysis is set to BLOCKED.
        When all conditions become 'DONE' then ctrled_analysis is set to READY
        The workers switch the analysis.status to 'WORKING' and 'DONE'.
        But any moment if a condition goes false, the analysis is reset to BLOCKED.

@column condition_analysis_url foreign key to net distributed analysis reference
@column ctrled_analysis_id     foreign key to analysis table analysis_id
*/

CREATE TABLE analysis_ctrl_rule (
    condition_analysis_url  VARCHAR(255) NOT NULL DEFAULT '',
    ctrled_analysis_id      INTEGER     NOT NULL,

    UNIQUE (condition_analysis_url, ctrled_analysis_id)
);


/**
@header Resources
@colour #FF7504
*/

/**
@table  resource_class

@colour #FF7504

@desc   Maps between resource_class numeric IDs and unique names.

@column resource_class_id   unique ID of the ResourceClass
@column name                unique name of the ResourceClass
*/

CREATE TABLE resource_class (
    resource_class_id       SERIAL PRIMARY KEY,
    name                    VARCHAR(255) NOT NULL,

    UNIQUE  (name)
);


/**
@table  resource_description

@colour #FF7504

@desc   Maps (ResourceClass, MeadowType) pair to Meadow-specific resource lines.

@column resource_class_id   foreign-keyed to the ResourceClass entry
@column meadow_type         if the Worker is about to be executed on the given Meadow...
@column submission_cmd_args ... these are the resource arguments (queue, memory,...) to give to the submission command
@column worker_cmd_args     ... and these are the arguments that are given to the worker command being submitted
*/

CREATE TABLE resource_description (
    resource_class_id       INTEGER     NOT NULL,
    meadow_type             VARCHAR(255) NOT NULL,
    submission_cmd_args     VARCHAR(255) NOT NULL DEFAULT '',
    worker_cmd_args         VARCHAR(255) NOT NULL DEFAULT '',

    PRIMARY KEY(resource_class_id, meadow_type)
);


/**
@header Job-related
@colour #1D73DA
*/

/**
@table  job

@colour #1D73DA

@desc The job is the heart of this system.  It is the kiosk or blackboard
    where workers find things to do and then post work for other works to do.
    These jobs are created prior to work being done, are claimed by workers,
    are updated as the work is done, with a final update on completion.

@column job_id                  autoincrement id
@column prev_job_id             previous job which created this one
@column analysis_id             the analysis_id needed to accomplish this job.
@column input_id                input data passed into Analysis:RunnableDB to control the work
@column param_id_stack          a CSV of job_ids whose input_ids contribute to the stack of local variables for the job
@column accu_id_stack           a CSV of job_ids whose accu's contribute to the stack of local variables for the job
@column role_id                 links to the Role that claimed this job (NULL means it has never been claimed)
@column status                  state the job is in
@column retry_count             number times job had to be reset when worker failed to run it
@column when_completed          when the job was completed
@column runtime_msec            how long did it take to execute the job (or until the moment it failed)
@column query_count             how many SQL queries were run during this job
@column semaphore_count         if this count is >0, the job is conditionally blocked (until this count drops to 0 or below). Default=0 means "nothing is blocking me by default".
@column semaphored_job_id       the job_id of job S that is waiting for this job to decrease S's semaphore_count. Default=NULL means "I'm not blocking anything by default".
*/

CREATE TABLE job (
    job_id                  SERIAL PRIMARY KEY,
    prev_job_id             INTEGER              DEFAULT NULL,  -- the job that created this one using a dataflow rule
    analysis_id             INTEGER     NOT NULL,
    input_id                TEXT        NOT NULL,
    param_id_stack          TEXT        NOT NULL DEFAULT '',
    accu_id_stack           TEXT        NOT NULL DEFAULT '',
    role_id                 INTEGER              DEFAULT NULL,
    status                  TEXT        NOT NULL DEFAULT 'READY',   -- expected values: 'SEMAPHORED','READY','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_HEALTHCHECK','POST_CLEANUP','DONE','FAILED','PASSED_ON'
    retry_count             INTEGER     NOT NULL DEFAULT 0,
    when_completed          TIMESTAMP            DEFAULT NULL,
    runtime_msec            INTEGER              DEFAULT NULL,
    query_count             INTEGER              DEFAULT NULL,

    semaphore_count         INTEGER     NOT NULL DEFAULT 0,
    semaphored_job_id       INTEGER              DEFAULT NULL,

    UNIQUE (input_id, param_id_stack, accu_id_stack, analysis_id)   -- to avoid repeating tasks
);
CREATE INDEX ON job (analysis_id, status, retry_count); -- for claiming jobs
CREATE INDEX ON job (role_id, status);                  -- for fetching and releasing claimed jobs


/**
@table  job_file

@colour #1D73DA

@desc   For testing/debugging purposes both STDOUT and STDERR streams of each Job
        can be redirected into a separate log file.
        This table holds filesystem paths to one or both of those files.
        There is max one entry per job_id and retry.

@column job_id             foreign key
@column role_id            links to the Role that claimed this job
@column retry              copy of retry_count of job as it was run
@column stdout_file        path to the job's STDOUT log
@column stderr_file        path to the job's STDERR log
*/

CREATE TABLE job_file (
    job_id                  INTEGER     NOT NULL,
    retry                   INTEGER     NOT NULL,
    role_id                 INTEGER     NOT NULL,
    stdout_file             VARCHAR(255),
    stderr_file             VARCHAR(255),

    PRIMARY KEY (job_id, retry)
);
CREATE INDEX ON job_file (role_id);


/**
@table  accu

@colour #1D73DA

@desc   Accumulator for funneled dataflow.

@column sending_job_id     semaphoring job in the "box"
@column receiving_job_id   semaphored job outside the "box"
@column struct_name        name of the structured parameter
@column key_signature      locates the part of the structured parameter
@column value              value of the part
*/

CREATE TABLE accu (
    sending_job_id          INTEGER,
    receiving_job_id        INTEGER     NOT NULL,
    struct_name             VARCHAR(255) NOT NULL,
    key_signature           VARCHAR(255) NOT NULL,
    value                   TEXT
);
CREATE INDEX ON accu (sending_job_id);
CREATE INDEX ON accu (receiving_job_id);


/**
@table  analysis_data

@colour #1D73DA

@desc   A generic blob-storage hash.
        Currently the only legitimate use of this table is "overflow" of job.input_ids:
        when they grow longer than 254 characters the real data is stored in analysis_data instead,
        and the input_id contains the corresponding analysis_data_id.

@column analysis_data_id    primary id
@column md5sum              checksum over the data to quickly detect (potential) collisions
@column data                text blob which holds the data
*/

CREATE TABLE analysis_data (
    analysis_data_id        SERIAL PRIMARY KEY,
    md5sum                  CHAR(32) NOT NULL,
    data                    TEXT     NOT NULL
);
CREATE INDEX ON analysis_data (md5sum);


/**
@header execution tables
@colour #24DA06
*/

/**
@table  worker

@colour #24DA06

@desc Entries of this table correspond to Worker objects of the API.
        Workers are created by inserting into this table
        so that there is only one instance of a Worker object in the database.
        As Workers live and do work, they update this table, and when they die they update again.

@column worker_id           unique ID of the Worker
@column meadow_type         type of the Meadow it is running on
@column meadow_name         name of the Meadow it is running on (for meadow_type=='LOCAL' it is the same as meadow_host)
@column meadow_host         execution host name
@column meadow_user         scheduling/execution user name (within the Meadow)
@column process_id          identifies the Worker process on the Meadow (for 'LOCAL' is the OS PID)
@column resource_class_id   links to Worker's resource class
@column work_done           how many jobs the Worker has completed successfully
@column status              current status of the Worker
@column when_born           when the Worker process was started
@column when_checked_in     when the Worker last checked into the database
@column when_seen           when the Worker was last seen by the Meadow
@column when_died           if defined, when the Worker died (or its premature death was first detected by GC)
@column cause_of_death      if defined, why did the Worker exit (or why it was killed)
@column log_dir             if defined, a filesystem directory where this Worker's output is logged
*/

CREATE TYPE worker_cod AS ENUM ('NO_ROLE', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'RELOCATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'SEE_MSG', 'UNKNOWN');
CREATE TABLE worker (
    worker_id               SERIAL PRIMARY KEY,
    meadow_type             VARCHAR(255) NOT NULL,
    meadow_name             VARCHAR(255) NOT NULL,
    meadow_host             VARCHAR(255) NOT NULL,
    meadow_user             VARCHAR(255)         DEFAULT NULL,
    process_id              VARCHAR(255) NOT NULL,
    resource_class_id       INTEGER              DEFAULT NULL,
    work_done               INTEGER      NOT NULL DEFAULT 0,
    status                  VARCHAR(255) NOT NULL DEFAULT 'READY',  -- expected values: 'SPECIALIZATION','COMPILATION','READY','JOB_LIFECYCLE','DEAD'
    when_born               TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    when_checked_in         TIMESTAMP            DEFAULT NULL,
    when_seen               TIMESTAMP            DEFAULT NULL,
    when_died               TIMESTAMP            DEFAULT NULL,
    cause_of_death          worker_cod           DEFAULT NULL,
    log_dir                 VARCHAR(255)         DEFAULT NULL
);
CREATE INDEX ON worker (meadow_type, meadow_name, process_id);


/**
@table  role

@colour #24DA06

@desc Entries of this table correspond to Role objects of the API.
        When a Worker specializes, it acquires a Role,
        which is a temporary link between the Worker and a resource-compatible Analysis.

@column role_id             unique ID of the Role
@column worker_id           the specialized Worker
@column analysis_id         the Analysis into which the Worker specialized
@column when_started        when this Role started
@column when_finished       when this Role finished. NULL may either indicate it is still running or was killed by an external force.
@column attempted_jobs      counter of the number of attempts
@column done_jobs           counter of the number of successful attempts
*/

CREATE TABLE role (
    role_id                 SERIAL PRIMARY KEY,
    worker_id               INTEGER     NOT NULL,
    analysis_id             INTEGER     NOT NULL,
    when_started            TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    when_finished           TIMESTAMP            DEFAULT NULL,
    attempted_jobs          INTEGER     NOT NULL DEFAULT 0,
    done_jobs               INTEGER     NOT NULL DEFAULT 0
);
CREATE        INDEX role_worker_id_idx ON role (worker_id);
CREATE        INDEX role_analysis_id_idx ON role (analysis_id);



/**
@header Logging and monitoring
@colour #F4D20C
*/

/**
@table  worker_resource_usage

@colour #F4D20C

@desc   A table with post-mortem resource usage statistics of a Worker.

@column          worker_id  links to the worker table
@column        exit_status  meadow-dependent, in case of LSF it's usually 'done' (normal) or 'exit' (abnormal)
@column           mem_megs  how much memory the Worker process used
@column          swap_megs  how much swap the Worker process used
@column        pending_sec  time spent by the process in the queue before it became a Worker
@column            cpu_sec  cpu time used by the Worker process
@column       lifespan_sec  walltime used by the Worker process
@column   exception_status  meadow-specific flags, in case of LSF it can be 'underrun', 'overrun' or 'idle'
*/

CREATE TABLE worker_resource_usage (
    worker_id               INTEGER         NOT NULL,
    exit_status             VARCHAR(255)    DEFAULT NULL,
    mem_megs                FLOAT           DEFAULT NULL,
    swap_megs               FLOAT           DEFAULT NULL,
    pending_sec             FLOAT           DEFAULT NULL,
    cpu_sec                 FLOAT           DEFAULT NULL,
    lifespan_sec            FLOAT           DEFAULT NULL,
    exception_status        VARCHAR(255)    DEFAULT NULL,

    PRIMARY KEY (worker_id)
);


/**
@table  log_message

@colour #F4D20C

@desc   When a Job or a job-less Worker (job_id=NULL) throws a "die" message
        for any reason, the message is recorded in this table.
        It may or may not indicate that the job was unsuccessful via is_error flag.
        Also $self->warning("...") messages are recorded with is_error=0.

@column log_message_id  an autoincremented primary id of the message
@column         job_id  the id of the job that threw the message (or NULL if it was outside of a message)
@column        role_id  the 'current' role
@column      worker_id  the 'current' worker
@column    when_logged  when the message was thrown
@column          retry  retry_count of the job when the message was thrown (or NULL if no job)
@column         status  of the job or worker when the message was thrown
@column            msg  string that contains the message
@column       is_error  binary flag
*/

CREATE TABLE log_message (
    log_message_id          SERIAL PRIMARY KEY,
    job_id                  INTEGER              DEFAULT NULL,
    role_id                 INTEGER              DEFAULT NULL,
    worker_id               INTEGER              DEFAULT NULL,
    when_logged             TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    retry                   INTEGER              DEFAULT NULL,
    status                  VARCHAR(255) NOT NULL DEFAULT 'UNKNOWN',
    msg                     TEXT,
    is_error                SMALLINT

);
CREATE INDEX ON log_message (worker_id);
CREATE INDEX ON log_message (job_id);


/**
@table  analysis_stats_monitor

@colour #F4D20C

@desc   A regular timestamped snapshot of the analysis_stats table.

@column when_logged             when this snapshot was taken

@column analysis_id             foreign-keyed to the corresponding analysis_base entry
@column batch_size              how many jobs are claimed in one claiming operation before Worker starts executing them
@column hive_capacity           a reciprocal limiter on the number of Workers running at the same time (dependent on Workers of other Analyses)
@column status                  cached state of the Analysis

@column total_job_count         total number of Jobs of this Analysis
@column semaphored_job_count    number of Jobs of this Analysis that are in SEMAPHORED state
@column ready_job_count         number of Jobs of this Analysis that are in READY state
@column done_job_count          number of Jobs of this Analysis that are in DONE state
@column failed_job_count        number of Jobs of this Analysis that are in FAILED state

@column num_running_workers     number of running Workers of this Analysis

@column behaviour               whether hive_capacity is set or is dynamically calculated based on timers
@column input_capacity          used to compute hive_capacity in DYNAMIC mode
@column output_capacity         used to compute hive_capacity in DYNAMIC mode

@column avg_msec_per_job        weighted average used to compute DYNAMIC hive_capacity
@column avg_input_msec_per_job  weighted average used to compute DYNAMIC hive_capacity
@column avg_run_msec_per_job    weighted average used to compute DYNAMIC hive_capacity
@column avg_output_msec_per_job weighted average used to compute DYNAMIC hive_capacity

@column when_updated            when this entry was last updated
@column sync_lock               a binary lock flag to prevent simultaneous updates
*/

CREATE TABLE analysis_stats_monitor (
    when_logged             TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    analysis_id             INTEGER     NOT NULL,
    batch_size              INTEGER     NOT NULL DEFAULT 1,
    hive_capacity           INTEGER              DEFAULT NULL,
    status                  analysis_status NOT NULL DEFAULT 'EMPTY',

    total_job_count         INTEGER     NOT NULL DEFAULT 0,
    semaphored_job_count    INTEGER     NOT NULL DEFAULT 0,
    ready_job_count         INTEGER     NOT NULL DEFAULT 0,
    done_job_count          INTEGER     NOT NULL DEFAULT 0,
    failed_job_count        INTEGER     NOT NULL DEFAULT 0,

    num_running_workers     INTEGER     NOT NULL DEFAULT 0,

    behaviour               analysis_behaviour NOT NULL DEFAULT 'STATIC',
    input_capacity          INTEGER     NOT NULL DEFAULT 4,
    output_capacity         INTEGER     NOT NULL DEFAULT 4,

    avg_msec_per_job        INTEGER              DEFAULT NULL,
    avg_input_msec_per_job  INTEGER              DEFAULT NULL,
    avg_run_msec_per_job    INTEGER              DEFAULT NULL,
    avg_output_msec_per_job INTEGER              DEFAULT NULL,

    when_updated            TIMESTAMP            DEFAULT NULL,
    sync_lock               SMALLINT    NOT NULL DEFAULT 0

);

