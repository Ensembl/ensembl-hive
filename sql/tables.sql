/*
    This is MySQL version of EnsEMBL Hive database schema file.
    
    It has been annotated with @-tags.
    The following command is used to create HTML documentation:
        perl $ENSEMBL_CVS_ROOT_DIR/ensembl/misc-scripts/sql2html.pl -i $ENSEMBL_CVS_ROOT_DIR/ensembl-hive/sql/tables.sql \
             -o $ENSEMBL_CVS_ROOT_DIR/ensembl-hive/docs/hive_schema.html -d Hive -sort_headers 0 -sort_tables 0

    Adding the following line into the header of the previous output will make it look prettier (valid in rel.71):
        <link rel="stylesheet" type="text/css" media="all" href="http://static.ensembl.org/minified/f75db6b3a877e4e04329aa1283dec34e.css" />
*/


/**
@header Pipeline structure
@colour #C70C09
*/

/**
@table  analysis_base

@colour #C70C09

@desc   Each Analysis is a node of the pipeline diagram.
        It acts both as a "class" to which Jobs belong (and inherit from it certain properties)
        and as a "container" for them (Jobs of an Analysis can be blocking all Jobs of another Analysis).

@column analysis_id             a unique ID that is also a foreign key to most of the other tables
@column logic_name              the name of the Analysis object
@column module                  the Perl module name that runs this Analysis
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
    analysis_id             int(10) unsigned NOT NULL AUTO_INCREMENT,
    logic_name              VARCHAR(40) NOT NULL,
    module                  VARCHAR(255),
    parameters              TEXT,
    resource_class_id       int(10) unsigned NOT NULL,
    failed_job_tolerance    int(10) DEFAULT 0 NOT NULL,
    max_retry_count         int(10) DEFAULT 3 NOT NULL,
    can_be_empty            TINYINT UNSIGNED DEFAULT 0 NOT NULL,
    priority                TINYINT DEFAULT 0 NOT NULL,
    meadow_type             varchar(40) DEFAULT NULL,
    analysis_capacity       int(10) DEFAULT NULL,

    PRIMARY KEY (analysis_id),
    UNIQUE  KEY logic_name_idx (logic_name)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


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
@column num_required_workers    extra number of Workers of this Analysis needed to execute all READY jobs

@column behaviour               whether hive_capacity is set or is dynamically calculated based on timers
@column input_capacity          used to compute hive_capacity in DYNAMIC mode
@column output_capacity         used to compute hive_capacity in DYNAMIC mode

@column avg_msec_per_job        weighted average used to compute DYNAMIC hive_capacity
@column avg_input_msec_per_job  weighted average used to compute DYNAMIC hive_capacity
@column avg_run_msec_per_job    weighted average used to compute DYNAMIC hive_capacity
@column avg_output_msec_per_job weighted average used to compute DYNAMIC hive_capacity

@column last_update             when this entry was last updated
@column sync_lock               a binary lock flag to prevent simultaneous updates
*/

CREATE TABLE analysis_stats (
    analysis_id             int(10) unsigned NOT NULL,
    batch_size              int(10) DEFAULT 1 NOT NULL,
    hive_capacity           int(10) DEFAULT NULL,
    status                  enum('BLOCKED', 'LOADING', 'SYNCHING', 'EMPTY', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE', 'FAILED') DEFAULT 'EMPTY' NOT NULL,

    total_job_count         int(10) DEFAULT 0 NOT NULL,
    semaphored_job_count    int(10) DEFAULT 0 NOT NULL,
    ready_job_count         int(10) DEFAULT 0 NOT NULL,
    done_job_count          int(10) DEFAULT 0 NOT NULL,
    failed_job_count        int(10) DEFAULT 0 NOT NULL,

    num_running_workers     int(10) DEFAULT 0 NOT NULL,
    num_required_workers    int(10) DEFAULT 0 NOT NULL,

    behaviour               enum('STATIC', 'DYNAMIC') DEFAULT 'STATIC' NOT NULL,
    input_capacity          int(10) DEFAULT 4 NOT NULL,
    output_capacity         int(10) DEFAULT 4 NOT NULL,

    avg_msec_per_job        int(10) DEFAULT NULL,
    avg_input_msec_per_job  int(10) DEFAULT NULL,
    avg_run_msec_per_job    int(10) DEFAULT NULL,
    avg_output_msec_per_job int(10) DEFAULT NULL,

    last_update             datetime NOT NULL default '0000-00-00 00:00:00',
    sync_lock               int(10) default 0 NOT NULL,

    PRIMARY KEY   (analysis_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  dataflow_rule

@colour #C70C09

@desc Extension of simple_rule design except that goal(to) is now in extended URL format e.g.
	mysql://ensadmin:<pass>@ecs2:3361/compara_hive_test?analysis.logic_name='blast_NCBI34'
	(full network address of an analysis).
	The only requirement is that there are rows in the job, analysis, dataflow_rule,
	and worker tables so that the following join works on the same database 
	   WHERE analysis.analysis_id = dataflow_rule.from_analysis_id 
	   AND   analysis.analysis_id = job.analysis_id
	   AND   analysis.analysis_id = worker.analysis_id
	These are the rules used to create entries in the job table where the
	input_id (control data) is passed from one analysis to the next to define work.
	The analysis table will be extended so that it can specify different read and write
	databases, with the default being the database the analysis is on

@column dataflow_rule_id     	internal ID
@column from_analysis_id     	foreign key to analysis table analysis_id
@column branch_code          	branch_code of the fan
@column funnel_dataflow_rule_id	dataflow_rule_id of the semaphored funnel (is NULL by default, which means dataflow is not semaphored)
@column to_analysis_url      	foreign key to net distributed analysis logic_name reference
@column input_id_template    	a template for generating a new input_id (not necessarily a hashref) in this dataflow; if undefined is kept original
*/

CREATE TABLE dataflow_rule (
    dataflow_rule_id    int(10) unsigned NOT NULL AUTO_INCREMENT,
    from_analysis_id    int(10) unsigned NOT NULL,
    branch_code         int(10) default 1 NOT NULL,
    funnel_dataflow_rule_id  int(10) unsigned default NULL,
    to_analysis_url     varchar(255) default '' NOT NULL,
    input_id_template   TEXT DEFAULT NULL,

    PRIMARY KEY (dataflow_rule_id),
    UNIQUE  KEY (from_analysis_id, branch_code, funnel_dataflow_rule_id, to_analysis_url, input_id_template(512))

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


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
    condition_analysis_url     varchar(255) default '' NOT NULL,
    ctrled_analysis_id         int(10) unsigned NOT NULL,

    UNIQUE  KEY (condition_analysis_url, ctrled_analysis_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  meta

@colour #000000

@desc This table comes from the Ensembl core schema.
	It is created here with the 'IF NOT EXISTS' option to avoid a potential clash
	 if we are dealing with core-hive hybrid that is created in the wrong order.
	At the moment meta table is used
		(1) for compatibility with the Core API ('schema_version'),
		(2) to keep some Hive-specific meta-information ('pipeline_name') and
		(3) to keep pipeline-wide parameters.

@column meta_id			auto-incrementing primary key, not really used per se
@column species_id		always 1, kept for compatibility with the Core API
@column	meta_key		the KEY of KEY-VALUE pairs
@column	meta_value		the VALUE of KEY-VALUE pairs
*/

CREATE TABLE IF NOT EXISTS meta (
    meta_id                     INT NOT NULL AUTO_INCREMENT,
    species_id                  INT UNSIGNED DEFAULT 1,
    meta_key                    VARCHAR(40) NOT NULL,
    meta_value                  TEXT NOT NULL,

    PRIMARY   KEY (meta_id),
    UNIQUE    KEY species_key_value_idx (species_id, meta_key, meta_value(255)),
              KEY species_value_idx (species_id, meta_value(255))

) COLLATE=latin1_swedish_ci ENGINE=MyISAM;


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
    resource_class_id   int(10) unsigned NOT NULL AUTO_INCREMENT,
    name                varchar(40) NOT NULL,

    PRIMARY KEY(resource_class_id),
    UNIQUE  KEY(name)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  resource_description

@colour #FF7504

@desc   Maps (ResourceClass, MeadowType) pair to Meadow-specific resource lines.

@column resource_class_id   foreign-keyed to the ResourceClass entry
@column meadow_type         if the Worker is about to be executed on the given Meadow...
@column parameters          ... the following resource line should be given to it.
*/

CREATE TABLE resource_description (
    resource_class_id     int(10) unsigned NOT NULL,
    meadow_type           varchar(40) NOT NULL,
    parameters            varchar(255) DEFAULT '' NOT NULL,

    PRIMARY KEY(resource_class_id, meadow_type)
) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


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
@column prev_job_id             previous job which created this one (and passed input_id)
@column analysis_id             the analysis_id needed to accomplish this job.
@column input_id                input data passed into Analysis:RunnableDB to control the work
@column worker_id               link to worker table to define which worker claimed this job
@column status                  state the job is in
@column retry_count             number times job had to be reset when worker failed to run it
@column completed               datetime when job was completed
@column runtime_msec            how long did it take to execute the job (or until the moment it failed)
@column query_count             how many SQL queries were run during this job
@column semaphore_count         if this count is >0, the job is conditionally blocked (until this count drops to 0 or below). Default=0 means "nothing is blocking me by default".
@column semaphored_job_id       the job_id of job S that is waiting for this job to decrease S's semaphore_count. Default=NULL means "I'm not blocking anything by default".
*/

CREATE TABLE job (
    job_id                    int(10) NOT NULL AUTO_INCREMENT,
    prev_job_id               int(10) DEFAULT NULL,  # the job that created this one using a dataflow rule
    analysis_id               int(10) unsigned NOT NULL,
    input_id                  char(255) NOT NULL,
    worker_id                 int(10) unsigned DEFAULT NULL,
    status                    enum('SEMAPHORED','READY','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL,
    retry_count               int(10) default 0 NOT NULL,
    completed                 datetime DEFAULT NULL,
    runtime_msec              int(10) default NULL,
    query_count               int(10) default NULL,

    semaphore_count           int(10) NOT NULL default 0,
    semaphored_job_id         int(10) DEFAULT NULL,

    PRIMARY KEY                         (job_id),
    UNIQUE  KEY input_id_analysis       (input_id, analysis_id),                -- to avoid repeating tasks
            KEY analysis_status_retry   (analysis_id, status, retry_count),     -- for claiming jobs
            KEY  worker_id              (worker_id, status)                     -- for fetching and releasing claimed jobs

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  job_file

@colour #1D73DA

@desc   For testing/debugging purposes both STDOUT and STDERR streams of each Job
        can be redirected into a separate log file.
        This table holds filesystem paths to one or both of those files.
        There is max one entry per job_id and retry.

@column job_id             foreign key
@column worker_id          link to worker table to define which worker claimed this job
@column retry              copy of retry_count of job as it was run
@column stdout_file        path to the job's STDOUT log
@column stderr_file        path to the job's STDERR log
*/

CREATE TABLE job_file (
    job_id                  int(10) NOT NULL,
    retry                   int(10) NOT NULL,
    worker_id               int(10) unsigned NOT NULL,
    stdout_file             varchar(255),
    stderr_file             varchar(255),

    PRIMARY KEY job_retry   (job_id, retry),
            KEY  worker_id  (worker_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  analysis_data

@colour #1D73DA

@desc   A generic blob-storage hash.
        Currently the only legitimate use of this table is "overflow" of job.input_ids:
        when they grow longer than 254 characters the real data is stored in analysis_data instead,
        and the input_id contains the corresponding analysis_data_id.

@column analysis_data_id    primary id
@column data                text blob which holds the data
*/

CREATE TABLE analysis_data (
    analysis_data_id  int(10) NOT NULL AUTO_INCREMENT,
    data              longtext,

    PRIMARY KEY (analysis_data_id),
            KEY (data(100))

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@header worker table
@colour #24DA06
*/

/**
@table  worker

@colour #24DA06

@desc Entries of this table correspond to Worker objects of the API.
	Workers are created by inserting into this table
	so that there is only one instance of a Worker object in the database.
	As Workers live and do work, they update this table, and when they die they update again.

@column worker_id		unique ID of the Worker
@column meadow_type		type of the Meadow it is running on
@column meadow_name		name of the Meadow it is running on (for 'LOCAL' type is the same as host)
@column host			execution host name
@column process_id		identifies the Worker process on the Meadow (for 'LOCAL' is the OS PID)
@column resource_class_id	links to Worker's resource class
@column analysis_id		Analysis the Worker is specified into
@column work_done		how many jobs the Worker has completed successfully
@column status			current status of the Worker
@column born			when the Worker process was started
@column last_check_in		when the Worker last checked into the database
@column died			if defined, when the Worker died (or its premature death was first detected by GC)
@column cause_of_death		if defined, why did the Worker exit (or why it was killed)
@column log_dir			if defined, a filesystem directory where this Worker's output is logged
*/

CREATE TABLE worker (
    worker_id           int(10) unsigned NOT NULL AUTO_INCREMENT,
    meadow_type         varchar(40) NOT NULL,
    meadow_name         varchar(40) NOT NULL,
    host	            varchar(40) NOT NULL,
    process_id          varchar(40) NOT NULL,
    resource_class_id   int(10) unsigned DEFAULT NULL,

    analysis_id      int(10) unsigned DEFAULT NULL,
    work_done        int(11) DEFAULT '0' NOT NULL,
    status           enum('SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DEAD') DEFAULT 'READY' NOT NULL,
    born	           timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_check_in    datetime NOT NULL,
    died             datetime DEFAULT NULL,
    cause_of_death   enum('NO_ROLE', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'SEE_MSG', 'UNKNOWN') DEFAULT NULL,
    log_dir          varchar(255) DEFAULT NULL,

    PRIMARY KEY (worker_id),
            KEY analysis_status (analysis_id, status)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@header Logging and monitoring
@colour #F4D20C
*/

/**
@table  log_message

@colour #08DAD8

@desc   When a Job or a job-less Worker (job_id=NULL) throws a "die" message
        for any reason, the message is recorded in this table.
        It may or may not indicate that the job was unsuccessful via is_error flag.
        Also $self->warning("...") messages are recorded with is_error=0.

@column log_message_id  an autoincremented primary id of the message
@column         job_id  the id of the job that threw the message (or NULL if it was outside of a message)
@column      worker_id  the 'current' worker
@column           time  when the message was thrown
@column          retry  retry_count of the job when the message was thrown (or NULL if no job)
@column         status  of the job or worker when the message was thrown
@column            msg  string that contains the message
@column       is_error  binary flag
*/

CREATE TABLE log_message (
    log_message_id            int(10) NOT NULL AUTO_INCREMENT,
    job_id                    int(10) DEFAULT NULL,
    worker_id                 int(10) unsigned NOT NULL,
    time                      timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    retry                     int(10) DEFAULT NULL,
    status                    enum('UNKNOWN','SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN',
    msg                       text,
    is_error                  TINYINT,

    PRIMARY KEY               (log_message_id),
            KEY worker_id     (worker_id),
            KEY job_id        (job_id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  analysis_stats_monitor

@colour #F4D20C

@desc   A regular timestamped snapshot of the analysis_stats table.

@column time                    when this snapshot was taken

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
@column num_required_workers    extra number of Workers of this Analysis needed to execute all READY jobs

@column behaviour               whether hive_capacity is set or is dynamically calculated based on timers
@column input_capacity          used to compute hive_capacity in DYNAMIC mode
@column output_capacity         used to compute hive_capacity in DYNAMIC mode

@column avg_msec_per_job        weighted average used to compute DYNAMIC hive_capacity
@column avg_input_msec_per_job  weighted average used to compute DYNAMIC hive_capacity
@column avg_run_msec_per_job    weighted average used to compute DYNAMIC hive_capacity
@column avg_output_msec_per_job weighted average used to compute DYNAMIC hive_capacity

@column last_update             when this entry was last updated
@column sync_lock               a binary lock flag to prevent simultaneous updates
*/

CREATE TABLE analysis_stats_monitor (
    time                    datetime NOT NULL default '0000-00-00 00:00:00',

    analysis_id             int(10) unsigned NOT NULL,
    batch_size              int(10) DEFAULT 1 NOT NULL,
    hive_capacity           int(10) DEFAULT NULL,
    status                  enum('BLOCKED', 'LOADING', 'SYNCHING', 'EMPTY', 'READY', 'WORKING', 'ALL_CLAIMED', 'DONE', 'FAILED') DEFAULT 'EMPTY' NOT NULL,

    total_job_count         int(10) DEFAULT 0 NOT NULL,
    semaphored_job_count    int(10) DEFAULT 0 NOT NULL,
    ready_job_count         int(10) DEFAULT 0 NOT NULL,
    done_job_count          int(10) DEFAULT 0 NOT NULL,
    failed_job_count        int(10) DEFAULT 0 NOT NULL,

    num_running_workers     int(10) DEFAULT 0 NOT NULL,
    num_required_workers    int(10) DEFAULT 0 NOT NULL,

    behaviour               enum('STATIC', 'DYNAMIC') DEFAULT 'STATIC' NOT NULL,
    input_capacity          int(10) DEFAULT 4 NOT NULL,
    output_capacity         int(10) DEFAULT 4 NOT NULL,

    avg_msec_per_job        int(10) DEFAULT NULL,
    avg_input_msec_per_job  int(10) DEFAULT NULL,
    avg_run_msec_per_job    int(10) DEFAULT NULL,
    avg_output_msec_per_job int(10) DEFAULT NULL,

    last_update             datetime NOT NULL default '0000-00-00 00:00:00',
    sync_lock               int(10) default 0 NOT NULL

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


/**
@table  monitor

@colour #F4D20C

@desc   A regular collated snapshot of the Worker table.

@column time            when this snapshot was taken
@column workers         number of running workers
@column throughput      average numb of completed Jobs per sec. of the hive (this number is calculated using running workers only)
@column per_worker      average numb of completed Jobs per sec. per Worker (this number is calculated using running workers only)
@column analysis        a comma-separated list of analyses running at the time of snapshot

*/

CREATE TABLE monitor (
    time                  datetime NOT NULL default '0000-00-00 00:00:00',
    workers               int(10) NOT NULL default '0',
    throughput            float default NULL,
    per_worker            float default NULL,
    analysis              varchar(255) default NULL  # not just one, but a list of logic_names

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;


# Auto add schema version to database (should be overridden by Compara's table.sql)
INSERT IGNORE INTO meta (species_id, meta_key, meta_value) VALUES (NULL, 'schema_version', '72');

