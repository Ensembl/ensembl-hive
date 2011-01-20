# Add can_be_empty column to analysis_stats and analysis_stats_monitor tables:

ALTER TABLE analysis_stats         ADD COLUMN can_be_empty          TINYINT UNSIGNED DEFAULT 0 NOT NULL;
ALTER TABLE analysis_stats_monitor ADD COLUMN can_be_empty          TINYINT UNSIGNED DEFAULT 0 NOT NULL;

