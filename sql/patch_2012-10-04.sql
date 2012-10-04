
# renaming unclaimed_job_count to ready_job_count and adding semaphored_job_count:

ALTER TABLE analysis_stats          CHANGE COLUMN unclaimed_job_count ready_job_count         int(10) DEFAULT 0 NOT NULL;
ALTER TABLE analysis_stats_monitor  CHANGE COLUMN unclaimed_job_count ready_job_count         int(10) DEFAULT 0 NOT NULL;

ALTER TABLE analysis_stats          ADD COLUMN semaphored_job_count int(10) DEFAULT 0 NOT NULL;
ALTER TABLE analysis_stats_monitor  ADD COLUMN semaphored_job_count int(10) DEFAULT 0 NOT NULL;
