ALTER TABLE analysis_stats ADD COLUMN max_retry_count int(10) DEFAULT 3 NOT NULL AFTER done_job_count;
ALTER TABLE analysis_stats ADD COLUMN failed_job_tolerance int(10) DEFAULT 0 NOT NULL AFTER max_retry_count;
