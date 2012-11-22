    # a new limiter column for the scheduler:
ALTER TABLE analysis_base ADD COLUMN analysis_capacity int(10) DEFAULT NULL;

    # allow NULL to be a valid value for hive_capacity (however not yet default) :
ALTER TABLE analysis_stats          MODIFY COLUMN hive_capacity int(10) DEFAULT 1;
ALTER TABLE analysis_stats_monitor  MODIFY COLUMN hive_capacity int(10) DEFAULT 1;
