
## Dropping 'BLOCKED' state (of Jobs) and adding 'SEMAPHORED' state that should simplify several things.

ALTER TABLE job MODIFY COLUMN status enum('SEMAPHORED','READY','CLAIMED','COMPILATION','PRE_CLEANUP','FETCH_INPUT','RUN','WRITE_OUTPUT','POST_CLEANUP','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;


## Add a more efficient 3-part index instead of older 4-part index (based on the schema/API change):

ALTER TABLE job ADD INDEX analysis_status_retry (analysis_id, status, retry_count);
