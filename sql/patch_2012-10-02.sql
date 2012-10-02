
# Move failed_job_tolerance, max_retry_count, can_be_empty and priority columns
# from analysis_stats and analysis_stats_monitor into analysis_base table.
#
# Do not bother deleting the original columns from analysis_stats and analysis_stats_monitor,
# just copy the data over.

ALTER TABLE analysis_base ADD COLUMN    failed_job_tolerance    int(10) DEFAULT 0 NOT NULL;
ALTER TABLE analysis_base ADD COLUMN    max_retry_count         int(10) DEFAULT 3 NOT NULL;
ALTER TABLE analysis_base ADD COLUMN    can_be_empty            TINYINT UNSIGNED DEFAULT 0 NOT NULL;
ALTER TABLE analysis_base ADD COLUMN    priority                TINYINT DEFAULT 0 NOT NULL;

UPDATE analysis_base a JOIN analysis_stats s USING(analysis_id)
    SET a.failed_job_tolerance = s.failed_job_tolerance
      , a.max_retry_count = s.max_retry_count
      , a.can_be_empty = s.can_be_empty
      , a.priority = s.priority;

