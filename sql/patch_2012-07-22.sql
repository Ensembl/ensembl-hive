
## At last rename GET_INPUT into FETCH_INPUT for consistency between the schema and the code (it seems to be harder to patch all the accumulated code):

ALTER TABLE worker      MODIFY COLUMN status enum('READY','COMPILATION','FETCH_INPUT','RUN','WRITE_OUTPUT','DEAD') DEFAULT 'READY' NOT NULL;
ALTER TABLE job         MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','FETCH_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;
ALTER TABLE job_message MODIFY COLUMN status enum('UNKNOWN', 'COMPILATION', 'FETCH_INPUT', 'RUN', 'WRITE_OUTPUT', 'PASSED_ON') DEFAULT 'UNKNOWN';

