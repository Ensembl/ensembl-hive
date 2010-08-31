
## By adding the 'KILLED_BY_USER' cause_of_death we make it clear that the only case of 'FATALITY' is when the process gets lost on or killed by the farm.

ALTER TABLE hive MODIFY COLUMN cause_of_death enum('', 'NO_WORK', 'JOB_LIMIT', 'HIVE_OVERLOAD', 'LIFESPAN', 'CONTAMINATED', 'KILLED_BY_USER', 'FATALITY') DEFAULT '' NOT NULL;

