    # make NULL to be the default valid value for hive_capacity :
ALTER TABLE analysis_stats          MODIFY COLUMN hive_capacity int(10) DEFAULT NULL;
ALTER TABLE analysis_stats_monitor  MODIFY COLUMN hive_capacity int(10) DEFAULT NULL;
