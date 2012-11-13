    # add 'SPECIALIZATION' both to worker.status and job_message.status (as job_message now also records messages from jobless workers) :
ALTER TABLE worker MODIFY COLUMN status           enum('SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE job_message MODIFY COLUMN status      enum('UNKNOWN','SPECIALIZATION','COMPILATION','READY','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','PASSED_ON') DEFAULT 'UNKNOWN';

    # add 'SEE_MSG' cause_of_death for causes that cannot be expressed in one word:
ALTER TABLE worker MODIFY COLUMN cause_of_death   enum('NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'SEE_MSG', 'UNKNOWN') DEFAULT NULL;

