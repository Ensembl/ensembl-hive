ALTER TABLE analysis_job ADD COLUMN runtime_msec int(10) default 0 NOT NULL, ADD COLUMN query_count int(10) default 0 NOT NULL;
ALTER TABLE analysis_stats ADD COLUMN sync_lock int(10) default 0 NOT NULL;

