
## It is indeed redundant (can be found by joining), but proved to be very convenient to have:

ALTER TABLE job_message ADD COLUMN analysis_id int(10) DEFAULT 0 NOT NULL AFTER worker_id;

UPDATE job_message m, analysis_job j SET m.analysis_id=j.analysis_id WHERE j.analysis_job_id=m.analysis_job_id;

