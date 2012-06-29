# renaming rc_id into resource_class_id throughout the schema:

ALTER TABLE resource_description    CHANGE COLUMN rc_id resource_class_id int(10) unsigned NOT NULL;
ALTER TABLE analysis_stats          CHANGE COLUMN rc_id resource_class_id int(10) unsigned NOT NULL;
ALTER TABLE analysis_stats_monitor  CHANGE COLUMN rc_id resource_class_id int(10) unsigned NOT NULL;

