    # add 'NO_ROLE' cause_of_death specifically for workers that could not specialize
ALTER TABLE worker MODIFY COLUMN cause_of_death   enum('NO_ROLE', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'SEE_MSG', 'UNKNOWN') DEFAULT NULL;

