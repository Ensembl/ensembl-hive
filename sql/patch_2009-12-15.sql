# adding simple counting semaphores:

ALTER TABLE analysis_job ADD COLUMN semaphore_count   int(10) NOT NULL default 0;
ALTER TABLE analysis_job ADD COLUMN semaphored_job_id int(10) DEFAULT NULL;

