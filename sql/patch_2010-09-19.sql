
## A new 'PASSED_ON' state is added to the Job to make it possible to dataflow from resource-overusing jobs recovered from dead workers:

ALTER TABLE analysis_job MODIFY COLUMN status enum('READY','BLOCKED','CLAIMED','COMPILATION','GET_INPUT','RUN','WRITE_OUTPUT','DONE','FAILED','PASSED_ON') DEFAULT 'READY' NOT NULL;

