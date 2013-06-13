ALTER TABLE analysis_job_file ADD COLUMN retry int(10) default 0 NOT NULL after analysis_job_id, ADD COLUMN hive_id int(10) default 0 NOT NULL after analysis_job_id, drop index analysis_job_id;
CREATE UNIQUE INDEX job_hive_type on analysis_job_file (analysis_job_id, hive_id, type);

