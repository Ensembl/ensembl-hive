# add the 'priority' column to analysis_stats and analysis_stats_monitor tables:

ALTER TABLE analysis_stats         ADD COLUMN priority TINYINT DEFAULT 0 NOT NULL;
ALTER TABLE analysis_stats_monitor ADD COLUMN priority TINYINT DEFAULT 0 NOT NULL;
