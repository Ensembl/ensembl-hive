
## New states that *may* be detected by timely LSF interrogation.

ALTER TABLE hive MODIFY COLUMN cause_of_death enum('', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'MEMLIMIT', 'RUNLIMIT', 'FATALITY') DEFAULT '' NOT NULL;

