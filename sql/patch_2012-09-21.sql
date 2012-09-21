
# Move resource_class_id from analysis_stats and analysis_stats_monitor into analysis_base table.
# Do not bother deleting the original column from analysis_stats and analysis_stats_monitor
# because of the already established foreign key relationships.

ALTER TABLE analysis_base ADD COLUMN resource_class_id           int(10) unsigned NOT NULL;

UPDATE analysis_base a JOIN analysis_stats s USING(analysis_id) SET a.resource_class_id=s.resource_class_id;

